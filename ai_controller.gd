extends Node
class_name AIController

enum Difficulty {
	NORMAL,
	HARD
}

var hex_grid: HexGrid
var difficulty: Difficulty = Difficulty.NORMAL
var team: int = -1
var aggression_level: float = 0.5

var params = {
	Difficulty.NORMAL: {
		"aggression": 0.5,
		"expansion_priority": 0.6,
		"defense_priority": 0.4,
		"economy_reserve": 30,
		"wall_threshold": 0.3,
		"think_time": 0.5,
	},
	Difficulty.HARD: {
		"aggression": 0.8,
		"expansion_priority": 0.7,
		"defense_priority": 0.7,
		"economy_reserve": 20,
		"wall_threshold": 0.5,
		"think_time": 0.3,
	}
}

var memory: Dictionary = {
	"last_attacked_by": {},
	"lost_territories": [],
	"previous_hex_count": 0,
	"enemy_strength_history": {},
	"danger_zones": [],
	"castle_under_attack": false,
	"castle_attacker_pos": Vector2i.ZERO
}

var strategic_goals: Array = []

func _init(grid: HexGrid, ai_team: int, diff: Difficulty = Difficulty.NORMAL, aggro: float = 0.5):
	hex_grid = grid
	team = ai_team
	difficulty = diff
	aggression_level = clamp(aggro, 0.1, 1.0)
	
	params[difficulty].aggression = aggression_level
	
	if aggression_level < 0.3:
		params[difficulty].defense_priority = 0.8
		params[difficulty].expansion_priority = 0.3
		params[difficulty].wall_threshold = 0.6
	elif aggression_level > 0.7:
		params[difficulty].defense_priority = 0.3
		params[difficulty].expansion_priority = 0.9
		params[difficulty].wall_threshold = 0.2

func has_team(obj) -> bool:
	return obj != null and is_instance_valid(obj) and "team" in obj

func get_object_team(obj) -> int:
	if has_team(obj):
		return obj.team
	return -1

func execute_turn():
	print("=== AI (Team %d, %s, Aggro: %.1f) zaczyna turę ===" % [team, "HARD" if difficulty == Difficulty.HARD else "NORMAL", aggression_level])
	
	var state = analyze_game_state()
	update_memory(state)
	set_strategic_goals(state)
	
	if team == -1:
		print("AI %d: Bandyci - tylko ruch jednostek" % team)
		await move_all_units(state)
		print("=== AI (Team %d) kończy turę ===" % team)
		return
	
	var is_bankrupt = hex_grid.team_gold.get(team, 0) < hex_grid.calculate_upkeep(team)
	
	# NAJPIERW RUCH - potem kupowanie (żeby zwolnić miejsce)
	await move_all_units(state)
	
	# Merge units
	await merge_units(state)
	
	# Kupuj jednostki
	if not is_bankrupt:
		await buy_units(state)
	else:
		print("AI %d: Bankructwo - pomijam kupowanie jednostek" % team)
	
	# Buduj mury POPRAWNIE
	if not is_bankrupt:
		await build_walls(state)
	
	print("=== AI (Team %d) kończy turę ===" % team)

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
		"undefended_enemy_castles": [],
		"walled_enemy_castles": [],
		"bandit_camps": [],
		"threats": [],
		"castle_threats": [],
		"opportunities": [],
		"cutoff_opportunities": [],
		"gold": hex_grid.team_gold.get(team, 0),
		"income": hex_grid.calculate_income(team),
		"upkeep": hex_grid.calculate_upkeep(team),
	}
	
	for coords in hex_grid.hex_map:
		var owner = hex_grid.territory_map.get(coords, 0)
		
		if owner == team:
			state.my_hexes.append(coords)
		elif owner > 0 and owner <= 4:
			state.enemy_hexes.append(coords)
		else:
			state.neutral_hexes.append(coords)
	
	state.my_connected_hexes = hex_grid.get_connected_territories(team)
	state.border_hexes = hex_grid.get_border_of_connected_territories(team, state.my_connected_hexes)
	
	# Zbieranie jednostek z walidacją
	for unit in hex_grid.knight_map.values():
		if not is_instance_valid(unit):
			continue
		if unit.team == team:
			state.my_units.append({"unit": unit, "type": "knight", "pos": unit.hex_position, "strength": 40})
		elif unit.team > 0 and unit.team <= 4:
			state.enemy_units.append({"unit": unit, "type": "knight", "pos": unit.hex_position, "team": unit.team, "strength": 40})
	
	for unit in hex_grid.farmer_map.values():
		if not is_instance_valid(unit):
			continue
		if unit.team == team:
			state.my_units.append({"unit": unit, "type": "farmer", "pos": unit.hex_position, "strength": 10})
		elif unit.team > 0 and unit.team <= 4:
			state.enemy_units.append({"unit": unit, "type": "farmer", "pos": unit.hex_position, "team": unit.team, "strength": 10})
	
	for unit in hex_grid.spearman_map.values():
		if not is_instance_valid(unit):
			continue
		if unit.team == team:
			state.my_units.append({"unit": unit, "type": "spearman", "pos": unit.hex_position, "strength": 20})
		elif unit.team > 0 and unit.team <= 4:
			state.enemy_units.append({"unit": unit, "type": "spearman", "pos": unit.hex_position, "team": unit.team, "strength": 20})
	
	for unit in hex_grid.cavalry_map.values():
		if not is_instance_valid(unit):
			continue
		if unit.team == team:
			state.my_units.append({"unit": unit, "type": "cavalry", "pos": unit.hex_position, "strength": 80})
		elif unit.team > 0 and unit.team <= 4:
			state.enemy_units.append({"unit": unit, "type": "cavalry", "pos": unit.hex_position, "team": unit.team, "strength": 80})
	
	for coords in hex_grid.castle_map:
		var castle = hex_grid.castle_map[coords]
		if castle.team == team:
			state.my_castles.append(coords)
			
			for enemy in state.enemy_units:
				var dist = hex_distance(enemy.pos, coords)
				if dist <= 3:
					state.castle_threats.append({
						"castle_pos": coords,
						"enemy": enemy,
						"distance": dist
					})
					memory.castle_under_attack = true
					memory.castle_attacker_pos = enemy.pos
		
		elif castle.team > 0 and castle.team <= 4:
			state.enemy_castles.append(coords)
			
			var walls_count = count_walls_around(coords)
			
			if is_castle_undefended(coords, castle.team):
				if walls_count >= 6:
					state.walled_enemy_castles.append(coords)
				else:
					state.undefended_enemy_castles.append(coords)
		elif castle.team == -1:
			state.bandit_camps.append(coords)
	
	# Możliwości odcięcia
	state.cutoff_opportunities = find_cutoff_opportunities_simple(state)
	
	for enemy in state.enemy_units:
		var dist_to_border = get_min_distance(enemy.pos, state.my_connected_hexes)
		if dist_to_border <= 2:
			state.threats.append(enemy)
	
	return state

func find_cutoff_opportunities_simple(state: Dictionary) -> Array:
	"""Prostsza wersja - sprawdza czy możemy odciąć jednostki"""
	var opportunities = []
	
	for enemy in state.enemy_units:
		if not enemy.has("team"):
			continue
		
		var enemy_pos = enemy.pos
		var enemy_team = enemy.team
		
		# Znajdź hexy wokół wroga które możemy zająć
		var neighbors = hex_grid.get_neighbors(enemy_pos)
		var occupiable = []
		
		for neighbor in neighbors:
			var hex = hex_grid.get_hex_at(neighbor)
			if not hex or hex.occupied_object != null:
				continue
			
			var owner = hex_grid.territory_map.get(neighbor, 0)
			if owner != enemy_team:  # Możemy zająć
				occupiable.append(neighbor)
		
		if occupiable.size() >= 2:
			# Ile naszych jednostek jest blisko?
			var our_nearby = 0
			for our_unit in state.my_units:
				if hex_distance(our_unit.pos, enemy_pos) <= 3:
					our_nearby += 1
			
			if our_nearby >= 2:
				opportunities.append({
					"type": "surround",
					"target_pos": enemy_pos,
					"target_strength": enemy.strength,
					"surrounding_hexes": occupiable,
					"priority": 100 + enemy.strength / 2
				})
	
	return opportunities

func is_castle_undefended(castle_pos: Vector2i, castle_team: int) -> bool:
	var neighbors = hex_grid.get_neighbors(castle_pos)
	
	for neighbor in neighbors:
		if hex_grid.knight_map.has(neighbor):
			var unit = hex_grid.knight_map[neighbor]
			if is_instance_valid(unit) and unit.team == castle_team:
				return false
		if hex_grid.spearman_map.has(neighbor):
			var unit = hex_grid.spearman_map[neighbor]
			if is_instance_valid(unit) and unit.team == castle_team:
				return false
		if hex_grid.cavalry_map.has(neighbor):
			var unit = hex_grid.cavalry_map[neighbor]
			if is_instance_valid(unit) and unit.team == castle_team:
				return false
	
	return true

func update_memory(state: Dictionary):
	var current_hex_count = state.my_connected_hexes.size()
	
	if current_hex_count < memory.previous_hex_count:
		print("AI %d: Straciłem terytorium!" % team)
	
	memory.previous_hex_count = current_hex_count
	
	if state.castle_threats.is_empty():
		memory.castle_under_attack = false
		memory.castle_attacker_pos = Vector2i.ZERO

func set_strategic_goals(state: Dictionary):
	strategic_goals.clear()
	
	# PRIORYTET #1: Obrona zamku
	if not state.castle_threats.is_empty():
		for threat in state.castle_threats:
			strategic_goals.append({
				"type": "defend_castle",
				"castle_pos": threat.castle_pos,
				"enemy_pos": threat.enemy.pos,
				"priority": 300,
			})
	
	# PRIORYTET #2: Zdobycie zamków
	for castle_pos in state.undefended_enemy_castles:
		strategic_goals.append({
			"type": "capture_castle",
			"position": castle_pos,
			"priority": 250,
			"target_team": hex_grid.castle_map[castle_pos].team
		})
	
	for castle_pos in state.walled_enemy_castles:
		strategic_goals.append({
			"type": "capture_walled_castle",
			"position": castle_pos,
			"priority": 220,
			"target_team": hex_grid.castle_map[castle_pos].team
		})
	
	# PRIORYTET #3: Odcinanie
	for opp in state.cutoff_opportunities:
		strategic_goals.append({
			"type": "surround_enemy",
			"data": opp,
			"priority": opp.priority
		})
	
	# Bandit camps
	for camp_pos in state.bandit_camps:
		var distance = get_min_unit_distance_to(camp_pos, state.my_units)
		if distance <= 5:
			strategic_goals.append({
				"type": "capture_bandit_camp",
				"position": camp_pos,
				"priority": 50,
			})
	
	# ZAWSZE dodaj ekspansję jako fallback
	strategic_goals.append({
		"type": "expand_territory",
		"priority": 10
	})
	
	strategic_goals.sort_custom(func(a, b): return a.priority > b.priority)
	
	print("AI %d: Cele strategiczne:" % team)
	for goal in strategic_goals:
		print("  - %s (priorytet: %d)" % [goal.type, goal.priority])

func get_min_unit_distance_to(target: Vector2i, units: Array) -> int:
	var min_dist = 999999
	for unit_data in units:
		var dist = hex_distance(unit_data.pos, target)
		if dist < min_dist:
			min_dist = dist
	return min_dist

func merge_units(state: Dictionary):
	# Farmers
	var farmers_by_pos = {}
	for unit_data in state.my_units:
		if unit_data.type == "farmer":
			farmers_by_pos[unit_data.pos] = unit_data
	
	var farmers_positions = farmers_by_pos.keys()
	for i in range(farmers_positions.size()):
		var pos1 = farmers_positions[i]
		if not hex_grid.farmer_map.has(pos1):
			continue
		
		for j in range(i + 1, farmers_positions.size()):
			var pos2 = farmers_positions[j]
			if not hex_grid.farmer_map.has(pos2):
				continue
			
			if are_hexes_adjacent(pos1, pos2):
				print("AI %d: Łączę farmerów %s + %s -> spearman" % [team, pos1, pos2])
				hex_grid.merge_farmers_to_spearman(pos1, pos2)
				await hex_grid.get_tree().create_timer(0.2).timeout
				break
	
	# Knights
	var knights_by_pos = {}
	for unit_data in state.my_units:
		if unit_data.type == "knight":
			knights_by_pos[unit_data.pos] = unit_data
	
	var knights_positions = knights_by_pos.keys()
	for i in range(knights_positions.size()):
		var pos1 = knights_positions[i]
		if not hex_grid.knight_map.has(pos1):
			continue
		
		for j in range(i + 1, knights_positions.size()):
			var pos2 = knights_positions[j]
			if not hex_grid.knight_map.has(pos2):
				continue
			
			if are_hexes_adjacent(pos1, pos2):
				print("AI %d: Łączę knightów %s + %s -> cavalry" % [team, pos1, pos2])
				hex_grid.merge_knights_to_cavalry(pos1, pos2)
				await hex_grid.get_tree().create_timer(0.2).timeout
				break

# ============================================================================
# KUPOWANIE JEDNOSTEK - NAPRAWIONE
# ============================================================================
func buy_units(state: Dictionary):
	var gold = state.gold
	var reserve = params[difficulty].economy_reserve
	var available_gold = max(0, gold - reserve)
	
	print("AI %d: Złoto: %d, Rezerwacja: %d, Dostępne: %d" % [team, gold, reserve, available_gold])
	
	if available_gold < hex_grid.FARMER_COST:
		print("AI %d: Za mało złota na jakąkolwiek jednostkę" % team)
		return
	
	var map_full = is_map_full()
	
	var units_to_buy = []
	if map_full:
		units_to_buy = plan_unit_purchases_aggressive(state, available_gold)
	else:
		units_to_buy = plan_unit_purchases_aggressive(state, available_gold)
	
	print("AI %d: Zaplanowano zakup %d jednostek" % [team, units_to_buy.size()])
	
	for purchase in units_to_buy:
		var unit_type = purchase.type
		var position = purchase.position
		var cost = purchase.cost
		
		if hex_grid.team_gold[team] < cost:
			print("AI %d: Brak złota na %s (koszt: %d, mam: %d)" % [team, unit_type, cost, hex_grid.team_gold[team]])
			continue
		
		# Sprawdź czy pole jest wolne
		var hex = hex_grid.get_hex_at(position)
		if not hex or hex.occupied_object != null:
			print("AI %d: Pole %s zajęte, pomijam" % [team, position])
			continue
		
		if unit_type == "farmer":
			hex_grid.place_farmer_at(position, team)
			hex_grid.team_gold[team] -= cost
			hex_grid.capture_territory(position, team)
			print("AI %d: ✓ Kupiono FARMER na %s za %d" % [team, position, cost])
		elif unit_type == "knight":
			hex_grid.place_knight_at(position, team)
			hex_grid.team_gold[team] -= cost
			hex_grid.capture_territory(position, team)
			print("AI %d: ✓ Kupiono KNIGHT na %s za %d" % [team, position, cost])
		elif unit_type == "spearman":
			hex_grid.place_spearman_at(position, team)
			hex_grid.team_gold[team] -= cost
			hex_grid.capture_territory(position, team)
			print("AI %d: ✓ Kupiono SPEARMAN na %s za %d" % [team, position, cost])
		elif unit_type == "cavalry":
			hex_grid.place_cavalry_at(position, team)
			hex_grid.team_gold[team] -= cost
			hex_grid.capture_territory(position, team)
			print("AI %d: ✓ Kupiono CAVALRY na %s za %d" % [team, position, cost])
		
		await hex_grid.get_tree().create_timer(0.1).timeout

func is_map_full() -> bool:
	for coords in hex_grid.hex_map:
		var owner = hex_grid.territory_map.get(coords, 0)
		if owner == 0:
			return false
	return true

func plan_unit_purchases_aggressive(state: Dictionary, budget: int) -> Array:
	"""NAPRAWIONE: Zawsze kupuj jednostki gdy masz kasę"""
	var purchases = []
	
	var spawn_positions = find_best_spawn_positions(state)
	
	if spawn_positions.is_empty():
		print("AI %d: Brak miejsca na spawn" % team)
		return purchases
	
	var remaining_budget = budget
	var aggression = params[difficulty].aggression
	
	print("AI %d: Dostępny budżet: %d, Pozycje spawnu: %d" % [team, remaining_budget, spawn_positions.size()])
	
	# Zamek zagrożony - KUP OBRONĘ
	if memory.castle_under_attack:
		while remaining_budget >= hex_grid.KNIGHT_COST and purchases.size() < 3:
			var pos = spawn_positions[purchases.size() % spawn_positions.size()]
			purchases.append({
				"type": "knight",
				"position": pos,
				"cost": hex_grid.KNIGHT_COST
			})
			remaining_budget -= hex_grid.KNIGHT_COST
			print("AI %d: [OBRONA] Planuję knight za %d" % [team, hex_grid.KNIGHT_COST])
		return purchases
	
	# Normalne kupowanie - ZAWSZE KUP COŚ!
	var units_bought = 0
	
	# Agresywny - kupuj knightów
	if aggression >= 0.7:
		while remaining_budget >= hex_grid.KNIGHT_COST and units_bought < 2 and units_bought < spawn_positions.size():
			var pos = spawn_positions[units_bought]
			purchases.append({
				"type": "knight",
				"position": pos,
				"cost": hex_grid.KNIGHT_COST
			})
			remaining_budget -= hex_grid.KNIGHT_COST
			units_bought += 1
			print("AI %d: [AGRESJA] Planuję knight za %d" % [team, hex_grid.KNIGHT_COST])
	
	# Kupuj farmerów dopóki mamy kasę
	while remaining_budget >= hex_grid.FARMER_COST and units_bought < 5 and units_bought < spawn_positions.size():
		var pos = spawn_positions[units_bought]
		purchases.append({
			"type": "farmer",
			"position": pos,
			"cost": hex_grid.FARMER_COST
		})
		remaining_budget -= hex_grid.FARMER_COST
		units_bought += 1
		print("AI %d: [EKONOMIA] Planuję farmer za %d" % [team, hex_grid.FARMER_COST])
	
	print("AI %d: Zaplanowano %d jednostek" % [team, purchases.size()])
	return purchases

func find_best_spawn_positions(state: Dictionary) -> Array:
	"""Znajduje NAJLEPSZE pozycje do spawnu - agresywne preferowane"""
	var positions = []
	
	if state.my_castles.is_empty():
		return positions
	
	var castle_pos = state.my_castles[0]
	var neighbors = hex_grid.get_neighbors(castle_pos)
	
	# PRIORYTET 1: Wrogie pola (przejmuj!)
	for neighbor in neighbors:
		if not hex_grid.hex_map.has(neighbor):
			continue
		
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex or hex.occupied_object != null:
			continue
		
		var owner = hex_grid.territory_map.get(neighbor, 0)
		
		if owner > 0 and owner != team:
			positions.append(neighbor)
			print("AI %d: Pozycja spawnu [WROGIE POLE]: %s" % [team, neighbor])
	
	# PRIORYTET 2: Neutralne pola
	if positions.size() < 3:
		for neighbor in neighbors:
			if neighbor in positions:
				continue
			
			if not hex_grid.hex_map.has(neighbor):
				continue
			
			var hex = hex_grid.get_hex_at(neighbor)
			if not hex or hex.occupied_object != null:
				continue
			
			var owner = hex_grid.territory_map.get(neighbor, 0)
			
			if owner == 0:
				positions.append(neighbor)
				print("AI %d: Pozycja spawnu [NEUTRALNE]: %s" % [team, neighbor])
	
	# PRIORYTET 3: Własne pola (ostateczność)
	if positions.size() < 3:
		for neighbor in neighbors:
			if neighbor in positions:
				continue
			
			if not hex_grid.hex_map.has(neighbor):
				continue
			
			var hex = hex_grid.get_hex_at(neighbor)
			if not hex or hex.occupied_object != null:
				continue
			
			var owner = hex_grid.territory_map.get(neighbor, 0)
			
			if owner == team:
				positions.append(neighbor)
				print("AI %d: Pozycja spawnu [WŁASNE]: %s" % [team, neighbor])
	
	return positions

# ============================================================================
# BUDOWANIE MURÓW - NAPRAWIONE (wszystkie 6 ścian!)
# ============================================================================
func build_walls(state: Dictionary):
	"""NAPRAWIONE: Używa create_hex_walls() jak gracz"""
	var hexes_to_wall = plan_hexes_for_walling(state)
	
	if hexes_to_wall.is_empty():
		return
	
	var walls_built = 0
	var max_hexes = 3  # Maksymalnie 3 hexy z murami na turę
	
	for hex_pos in hexes_to_wall:
		if walls_built >= max_hexes:
			break
		
		# Koszt za cały hex (6 ścian)
		var cost = hex_grid.WALL_COST_PER_HEX
		if hex_grid.team_gold[team] < cost:
			break
		
		# UŻYJ FUNKCJI HEX_GRID!
		var walls_created = hex_grid.create_hex_walls(hex_pos, team)
		
		if walls_created > 0:
			hex_grid.team_gold[team] -= cost
			walls_built += 1
			print("AI %d: Zbudowano %d murów wokół %s za %d złota" % [team, walls_created, hex_pos, cost])
		
		await hex_grid.get_tree().create_timer(0.1).timeout

func plan_hexes_for_walling(state: Dictionary) -> Array:
	"""Zwraca listę hexów które powinny dostać mury (wszystkie 6 ścian)"""
	var hexes = []
	
	# PRIORYTET 1: Zamek
	if memory.castle_under_attack:
		for castle_pos in state.my_castles:
			if count_walls_around(castle_pos) < 6:
				hexes.append(castle_pos)
	
	# PRIORYTET 2: Silne jednostki
	for unit_data in state.my_units:
		if unit_data.type in ["cavalry", "knight"]:
			if count_walls_around(unit_data.pos) < 6:
				hexes.append(unit_data.pos)
	
	return hexes

# ============================================================================
# RUCH JEDNOSTEK - Z LEAPFROGGIEM
# ============================================================================
func move_all_units(state: Dictionary):
	"""Rusza WSZYSTKIE jednostki - z logiką leapfrogu"""
	print("AI %d: === Rozpoczynam ruch %d jednostek ===" % [team, state.my_units.size()])
	
	var sorted_goals = strategic_goals.duplicate()
	sorted_goals.sort_custom(func(a, b): return a.priority > b.priority)
	
	# Obrona zamku
	if memory.castle_under_attack:
		await defend_castle_all_units(state)
		return
	
	# Zdobycie zamków
	await capture_enemy_castles(state, sorted_goals)
	
	# Odcinanie wrogów
	await surround_enemies(state, sorted_goals)
	
	# RESZTA - AGRESYWNA EKSPANSJA Z LEAPFROGGIEM
	await expand_aggressively_with_leapfrog(state, sorted_goals)
	
	print("AI %d: === Zakończono ruch jednostek ===" % team)

func capture_enemy_castles(state: Dictionary, goals: Array):
	"""Wysyła jednostki bojowe do zajęcia zamków"""
	
	for goal in goals:
		if goal.type not in ["capture_castle", "capture_walled_castle"]:
			continue
		
		var castle_pos = goal.position
		
		# Znajdź najbliższą jednostkę bojową
		var best_unit = null
		var min_dist = 999999
		
		for unit_data in state.my_units:
			if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
				continue
			
			var unit_type = unit_data.type
			var can_capture = false
			
			if goal.type == "capture_walled_castle":
				can_capture = unit_type in ["knight", "cavalry"]
			else:
				can_capture = unit_type in ["spearman", "knight", "cavalry"]
			
			if can_capture:
				var dist = hex_distance(unit_data.pos, castle_pos)
				if dist < min_dist:
					min_dist = dist
					best_unit = unit_data
		
		if best_unit:
			var moves = get_possible_moves(best_unit.type, best_unit.pos)
			
			if castle_pos in moves:
				print("AI %d: %s ZAJMUJE ZAMEK %s!" % [team, best_unit.type, castle_pos])
				await execute_move(best_unit.unit, best_unit, castle_pos)
			else:
				var best_move = find_closest_move(best_unit.pos, moves, castle_pos)
				if best_move != Vector2i.ZERO:
					print("AI %d: %s -> %s (cel: zamek %s)" % [team, best_unit.type, best_move, castle_pos])
					await execute_move(best_unit.unit, best_unit, best_move)

func surround_enemies(state: Dictionary, goals: Array):
	"""Otacza wrogów wieloma jednostkami naraz"""
	
	for goal in goals:
		if goal.type != "surround_enemy":
			continue
		
		var data = goal.data
		var target_pos = data.target_pos
		var surrounding_hexes = data.surrounding_hexes
		
		print("AI %d: OTACZAM WROGA na %s" % [team, target_pos])
		
		# Znajdź jednostki do otoczenia
		var available_units = []
		for unit_data in state.my_units:
			if is_instance_valid(unit_data.unit) and unit_data.unit not in hex_grid.units_moved_this_turn:
				var dist = hex_distance(unit_data.pos, target_pos)
				if dist <= 3:
					available_units.append(unit_data)
		
		# Sortuj po odległości
		available_units.sort_custom(func(a, b):
			return hex_distance(a.pos, target_pos) < hex_distance(b.pos, target_pos)
		)
		
		# Przypisz jednostki do hexów otaczających
		var assignments = min(available_units.size(), surrounding_hexes.size())
		
		for i in range(assignments):
			var unit_data = available_units[i]
			var target_hex = surrounding_hexes[i]
			
			var moves = get_possible_moves(unit_data.type, unit_data.pos)
			var best_move = find_closest_move(unit_data.pos, moves, target_hex)
			
			if best_move != Vector2i.ZERO:
				print("AI %d: %s otacza -> %s" % [team, unit_data.type, best_move])
				await execute_move(unit_data.unit, unit_data, best_move)

func expand_aggressively_with_leapfrog(state: Dictionary, goals: Array):
	"""KLUCZOWE: Jednostki mijają się i wychodzą na prowadzenie (LEAPFROG)"""
	
	print("AI %d: EKSPANSJA Z LEAPFROGGIEM" % team)
	
	# Posortuj jednostki od najdalszych od zamku (te z tyłu idą do przodu!)
	var units_to_move = []
	for unit_data in state.my_units:
		if is_instance_valid(unit_data.unit) and unit_data.unit not in hex_grid.units_moved_this_turn:
			units_to_move.append(unit_data)
	
	if units_to_move.is_empty():
		return
	
	var castle_pos = state.my_castles[0] if not state.my_castles.is_empty() else Vector2i.ZERO
	
	# SORTUJ: najbliższe wrogów/granicy - IDń PIERWSZE (agresywne leapfrogging)
	units_to_move.sort_custom(func(a, b):
		var a_to_enemy = 999999
		var b_to_enemy = 999999
		
		for enemy in state.enemy_units:
			a_to_enemy = min(a_to_enemy, hex_distance(a.pos, enemy.pos))
			b_to_enemy = min(b_to_enemy, hex_distance(b.pos, enemy.pos))
		
		# Bliższe wrogowi idą PIERWSZE
		return a_to_enemy < b_to_enemy
	)
	
	print("AI %d: Ruszam %d jednostek w kolejności agresywnej" % [team, units_to_move.size()])
	
	for unit_data in units_to_move:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var moves = get_possible_moves(unit_data.type, unit_data.pos)
		
		if moves.is_empty():
			continue
		
		# Znajdź NAJLEPSZY ruch - PREFERUJ LEAPFROG
		var best_move = find_best_leapfrog_move(unit_data, moves, state)
		
		if best_move != Vector2i.ZERO:
			print("AI %d: %s leapfrog %s -> %s" % [team, unit_data.type, unit_data.pos, best_move])
			await execute_move(unit_data.unit, unit_data, best_move)

func find_best_leapfrog_move(unit_data: Dictionary, moves: Array, state: Dictionary) -> Vector2i:
	"""KLUCZOWE: Preferuj ruchy które wyprzedzają sojuszników"""
	
	var best_move = Vector2i.ZERO
	var best_score = -999999
	
	# Znajdź najbliższych sojuszników
	var nearest_allies = []
	for ally in state.my_units:
		if ally.pos == unit_data.pos:
			continue
		var dist = hex_distance(unit_data.pos, ally.pos)
		if dist <= 2:
			nearest_allies.append(ally)
	
	for move in moves:
		var score = 0
		var owner = hex_grid.territory_map.get(move, 0)
		
		# BONUS: Wrogie pola
		if owner > 0 and owner != team:
			score += 30
		elif owner == 0:
			score += 20
		
		# BONUS: LEAPFROG - im dalej od sojuszników tym lepiej!
		var min_ally_dist = 999999
		for ally in nearest_allies:
			var dist_from_ally = hex_distance(move, ally.pos)
			min_ally_dist = min(min_ally_dist, dist_from_ally)
		
		if min_ally_dist >= 2:
			score += 50  # DUŻY BONUS za oddalenie się od sojuszników!
		
		# BONUS: Blisko wrogów
		if not state.enemy_units.is_empty():
			var min_enemy_dist = 999999
			for enemy in state.enemy_units:
				var dist = hex_distance(move, enemy.pos)
				min_enemy_dist = min(min_enemy_dist, dist)
			
			score += max(0, 20 - min_enemy_dist * 3)
		
		if score > best_score:
			best_score = score
			best_move = move
	
	return best_move

func defend_castle_all_units(state: Dictionary):
	"""Wszystkie jednostki bronią zamku"""
	
	if state.my_castles.is_empty():
		return
	
	var castle_pos = state.my_castles[0]
	
	for threat in state.castle_threats:
		var threat_pos = threat.enemy.pos
		
		for unit_data in state.my_units:
			if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
				continue
			
			var moves = get_possible_moves(unit_data.type, unit_data.pos)
			var best_move = find_closest_move(unit_data.pos, moves, threat_pos)
			
			if best_move != Vector2i.ZERO:
				await execute_move(unit_data.unit, unit_data, best_move)

func find_closest_move(from: Vector2i, moves: Array, target: Vector2i) -> Vector2i:
	var best_move = Vector2i.ZERO
	var min_dist = 999999
	
	for move in moves:
		var dist = hex_distance(move, target)
		if dist < min_dist:
			min_dist = dist
			best_move = move
	
	return best_move

func execute_move(unit, unit_data: Dictionary, target: Vector2i):
	if not is_instance_valid(unit):
		return
	
	var from = unit_data.pos
	
	if unit_data.type == "knight":
		hex_grid.move_knight(from, target)
	elif unit_data.type == "farmer":
		hex_grid.move_farmer(from, target)
	elif unit_data.type == "spearman":
		hex_grid.move_spearman(from, target)
	elif unit_data.type == "cavalry":
		hex_grid.move_cavalry(from, target)
	
	await hex_grid.get_tree().create_timer(0.15).timeout

# ============================================================================
# FUNKCJE POMOCNICZE
# ============================================================================
func get_possible_moves(unit_type: String, from: Vector2i) -> Array:
	match unit_type:
		"farmer":
			return get_farmer_moves(from)
		"spearman":
			return get_spearman_moves(from)
		"knight":
			return get_knight_moves(from)
		"cavalry":
			return get_cavalry_moves(from)
		_:
			return []

func get_farmer_moves(from: Vector2i) -> Array:
	var moves = []
	var neighbors = hex_grid.get_neighbors(from)
	
	for neighbor in neighbors:
		if not hex_grid.hex_map.has(neighbor):
			continue
		
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex:
			continue
		
		var owner = hex_grid.territory_map.get(neighbor, 0)
		
		if owner == 0 and hex.occupied_object == null:
			if not is_blocked_by_wall(from, neighbor):
				moves.append(neighbor)
	
	return moves

func get_spearman_moves(from: Vector2i) -> Array:
	var moves = []
	var neighbors = hex_grid.get_neighbors(from)
	
	for neighbor in neighbors:
		if not hex_grid.hex_map.has(neighbor):
			continue
		
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex:
			continue
		
		var owner = hex_grid.territory_map.get(neighbor, 0)
		var target = hex.occupied_object
		
		if owner == 0 or owner != team:
			if target == null:
				moves.append(neighbor)
			elif target is Farmer:
				var target_team = get_object_team(target)
				if target_team != team:
					moves.append(neighbor)
	
	return moves

func get_knight_moves(from: Vector2i) -> Array:
	var moves = []
	var neighbors = hex_grid.get_neighbors(from)
	
	for neighbor in neighbors:
		if not hex_grid.hex_map.has(neighbor):
			continue
		
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex:
			continue
		
		var owner = hex_grid.territory_map.get(neighbor, 0)
		var target = hex.occupied_object
		
		if owner == 0 or owner != team:
			if target == null:
				if not is_blocked_by_wall(from, neighbor):
					moves.append(neighbor)
			elif target is Farmer or target is Spearman:
				var target_team = get_object_team(target)
				if target_team != team:
					moves.append(neighbor)
	
	return moves

func get_cavalry_moves(from: Vector2i) -> Array:
	var moves = []
	var range2_hexes = get_hexes_in_range_manual(from, 2)
	
	for target_pos in range2_hexes:
		if not hex_grid.hex_map.has(target_pos):
			continue
		
		var hex = hex_grid.get_hex_at(target_pos)
		if not hex:
			continue
		
		var owner = hex_grid.territory_map.get(target_pos, 0)
		var target = hex.occupied_object
		
		if owner == 0 or owner != team:
			if target == null:
				moves.append(target_pos)
			elif not (target is Cavalry):
				var target_team = get_object_team(target)
				if target_team != team:
					moves.append(target_pos)
	
	return moves

func get_hexes_in_range_manual(center: Vector2i, range_dist: int) -> Array:
	var hexes = []
	
	for q in range(center.x - range_dist, center.x + range_dist + 1):
		for r in range(center.y - range_dist, center.y + range_dist + 1):
			var hex_pos = Vector2i(q, r)
			
			if hex_distance(center, hex_pos) <= range_dist:
				hexes.append(hex_pos)
	
	return hexes

func is_blocked_by_wall(from: Vector2i, to: Vector2i) -> bool:
	return hex_grid.has_wall_between(from, to)

func count_walls_around(pos: Vector2i) -> int:
	var count = 0
	var neighbors = hex_grid.get_neighbors(pos)
	
	for neighbor in neighbors:
		if hex_grid.has_wall_between(pos, neighbor):
			count += 1
	
	return count

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

func are_hexes_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var neighbors = hex_grid.get_neighbors(a)
	return b in neighbors
