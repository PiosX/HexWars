extends Node
class_name AIController

const DEBUG = false

enum Difficulty {
	NORMAL,
	HARD
}

enum Strategy {
	EXPANSION,      # Łączenie oddalonych terytoriów
	AGGRESSIVE,     # Atak na królestwo
	DEFENSIVE,      # Obrona i konsolidacja
	OPPORTUNISTIC   # Bandit camps i łatwe cele
}

var hex_grid: HexGrid
var difficulty: Difficulty = Difficulty.NORMAL
var team: int = -1
var aggression_level: float = 0.5
var current_strategy: Strategy = Strategy.EXPANSION

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
	"castle_attacker_pos": Vector2i.ZERO,
	"detached_territories": [],  # Odłączone terytoria
	"expansion_targets": []       # Cele ekspansji
}

var strategic_goals: Array = []
var isolated_units_freeze: Dictionary = {}  # NOWE: {unit_instance: turn_isolated}
var units_moved_on_own_territory: Dictionary = {}  # NOWE: {unit_instance: true} - jednostki które już przeszły po swoim terenie w tej turze
var unit_own_territory_turns: Dictionary = {}  # {unit: ile_tur_na_własnym}
var unit_last_positions: Dictionary = {}

# ============================================================================
# INITIALIZATION
# ============================================================================

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

# ============================================================================
# MAIN TURN EXECUTION
# ============================================================================

func _get_my_kingdom_ids() -> Array:
	"""Zwraca listę kingdom_id wszystkich zamków tego teamu."""
	var kids = []
	for coords in hex_grid.castle_map:
		if hex_grid.castle_map[coords].team == team:
			var kid = hex_grid.castle_kingdom_id.get(coords, 0)
			if kid > 0 and kid not in kids:
				kids.append(kid)
	return kids
	
func _is_interrupted() -> bool:
	return not hex_grid.ai_is_playing

func execute_turn():
	if DEBUG: print("=== AI (Team %d, %s, Aggro: %.1f) zaczyna turę ===" % [team, "HARD" if difficulty == Difficulty.HARD else "NORMAL", aggression_level])
	
	# Wyczyść tracking jednostek które były na swoim terenie
	units_moved_on_own_territory.clear()
	
	var state = analyze_game_state()
	update_memory(state)
	decide_strategy(state)
	set_strategic_goals(state)
	
	if team == -1:
		if DEBUG: print("AI %d: BANDYCI - proste AI" % team)
		await execute_bandit_turn(state)
		if DEBUG: print("=== AI (Team %d) kończy turę ===" % team)
		return
	
	# NAJPIERW MERGE - żeby scalone jednostki mogły od razu ruszyć (zamek pod atakiem!)
	if _is_interrupted(): return
	await merge_units(state)
	
	# Odśwież stan po merge (nowe jednostki mogą teraz atakować)
	if _is_interrupted(): return
	state = analyze_game_state()
	update_memory(state)
	decide_strategy(state)
	set_strategic_goals(state)
	
	# RUCH - scalone jednostki już mogą atakować
	if _is_interrupted(): return
	await move_all_units(state)
	
	# Kupuj jednostki i buduj mury - OSOBNO DLA KAŻDEGO KRÓLESTWA
	if _is_interrupted(): return
	var all_kingdom_ids = _get_my_kingdom_ids()
	for kid in all_kingdom_ids:
		# Ustaw aktywne królestwo
		hex_grid.selected_kingdom_per_team[team] = kid
		
		var k_gold = hex_grid.kingdom_gold.get(kid, 0)
		var k_upkeep = hex_grid.calculate_upkeep_for_kingdom(kid)
		var k_income = hex_grid.calculate_income_for_kingdom(kid)
		var k_is_bankrupt = k_gold < k_upkeep
		
		# Zaktualizuj state.gold/upkeep/income dla tego królestwa
		state.gold = k_gold
		state.upkeep = k_upkeep
		state.income = k_income
		
		if DEBUG: print("AI %d: Kingdom %d - złoto: %d, utrzymanie: %d, bankrut: %s" % [team, kid, k_gold, k_upkeep, k_is_bankrupt])
		
		if not k_is_bankrupt:
			await buy_units(state, kid)
		else:
			if DEBUG: print("AI %d: Kingdom %d bankrutuje - pomijam zakup" % [team, kid])
		
		# Buduj mury tylko gdy dodatni przychód netto
		if not k_is_bankrupt and k_income - k_upkeep > 0:
			await build_walls(state)
	
	if DEBUG: print("=== AI (Team %d) kończy turę ===" % team)

# ============================================================================
# GAME STATE ANALYSIS
# ============================================================================

func analyze_game_state() -> Dictionary:
	var state = {
		"my_hexes": [],
		"my_connected_hexes": [],
		"my_detached_groups": [],  # Grupy odłączonych pól
		"ally_castles_to_connect": [],  # Zamki sojusznika do połączenia
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
		"bandits": [],
		"threats": [],
		"castle_threats": [],
		"opportunities": [],
		"cutoff_opportunities": [],
		"enemy_kingdoms": {},  # Analiza sił wrogich królestw
		"gold": hex_grid.get_selected_kingdom_gold(team),
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
	
	# Znajdź główne połączone terytorium
	state.my_connected_hexes = hex_grid.get_connected_territories(team)
	state.border_hexes = hex_grid.get_border_of_connected_territories(team, state.my_connected_hexes)
	
	# Znajdź odłączone grupy terytoriów
	state.my_detached_groups = find_detached_territory_groups(state)
	
	# NOWE: Znajdź odłączone zamki sojusznika (tego samego koloru) do połączenia
	state.ally_castles_to_connect = find_ally_castles_to_connect(state)
	
	# Zbierz jednostki
	collect_units(state)
	
	# Zbierz zamki i obozy
	collect_castles_and_camps(state)
	
	# Analiza sił wrogich królestw
	state.enemy_kingdoms = analyze_enemy_kingdoms(state)
	
	# Możliwości odcięcia
	state.cutoff_opportunities = find_cutoff_opportunities(state)
	
	# NOWE: Zagrożenia odcięcia naszych jednostek przez wrogów
	state.cutoff_threats = find_cutoff_threats(state)
	
	# Zagrożenia
	for enemy in state.enemy_units:
		var dist_to_border = get_min_distance(enemy.pos, state.my_connected_hexes)
		if dist_to_border <= 2:
			state.threats.append(enemy)
	
	return state

func find_detached_territory_groups(state: Dictionary) -> Array:
	"""Znajduje wszystkie odłączone grupy terytoriów AI"""
	var groups = []
	var visited = {}
	
	# Oznacz główne terytorium jako odwiedzone
	for hex_pos in state.my_connected_hexes:
		visited[hex_pos] = true
	
	# Znajdź wszystkie odłączone hexy
	for hex_pos in state.my_hexes:
		if visited.get(hex_pos, false):
			continue
		
		# Nowa grupa - flood fill
		var group = flood_fill_territory(hex_pos, team, visited)
		
		if group.size() > 0:
			var group_data = {
				"hexes": group,
				"size": group.size(),
				"center": calculate_center(group),
				"distance_to_main": 999999,
				"distance_to_castle": 999999,
				"nearby_enemies": [],
				"safe": true,
				"worth_connecting": false
			}
			
			# Oblicz odległość do głównego terytorium
			if not state.my_connected_hexes.is_empty():
				group_data.distance_to_main = get_min_distance(group_data.center, state.my_connected_hexes)
			
			# Oblicz odległość do zamku
			if not state.my_castles.is_empty():
				group_data.distance_to_castle = get_min_distance(group_data.center, state.my_castles)
			
			# Sprawdź czy bezpieczne (>3 pola od wrogów)
			for enemy_castle in state.enemy_castles:
				var dist = hex_distance(group_data.center, enemy_castle)
				if dist <= 3:
					group_data.safe = false
					group_data.nearby_enemies.append({
						"pos": enemy_castle,
						"distance": dist,
						"type": "castle"
					})
			
			# Oceń czy warto połączyć
			group_data.worth_connecting = evaluate_group_worth(group_data, state)
			
			groups.append(group_data)
	
	# Sortuj grupy według wartości
	groups.sort_custom(func(a, b): 
		if a.worth_connecting != b.worth_connecting:
			return a.worth_connecting
		return a.size > b.size
	)
	
	return groups

func find_ally_castles_to_connect(state: Dictionary) -> Array:
	"""Znajdź zamki sojusznika (ten sam kolor, inny kingdom_id) które można połączyć.
	Zwraca listę {castle_pos, kingdom_id, distance} posortowaną po odległości."""
	var result = []
	
	if not "castle_kingdom_id" in hex_grid:
		return result
	
	# Znajdź wszystkie zamki tego samego teamu
	var my_castle_ids = {}  # {kingdom_id: true}
	var other_castle_ids = {}  # {kingdom_id: castle_pos}
	
	# Królestwa połączone z głównym terytorium
	for coords in hex_grid.castle_map:
		if hex_grid.castle_map[coords].team != team:
			continue
		var kid = hex_grid.castle_kingdom_id.get(coords, 0)
		if kid <= 0:
			continue
		if coords in state.my_connected_hexes:
			my_castle_ids[kid] = true
		else:
			other_castle_ids[kid] = coords
	
	# Znajdź zamki odłączone (inne kingdom_id, nie połączone z głównym)
	for kid in other_castle_ids:
		if my_castle_ids.has(kid):
			continue  # Ten kid jest już połączony
		var castle_pos = other_castle_ids[kid]
		var dist = get_min_distance(castle_pos, state.my_connected_hexes)
		result.append({
			"castle_pos": castle_pos,
			"kingdom_id": kid,
			"distance": dist
		})
	
	# Sortuj po odległości
	result.sort_custom(func(a, b): return a.distance < b.distance)
	return result

func flood_fill_territory(start: Vector2i, owner_team: int, visited: Dictionary) -> Array:
	"""Flood fill do znajdowania połączonych terytoriów"""
	var result = []
	var queue = [start]
	visited[start] = true
	
	while not queue.is_empty():
		var current = queue.pop_front()
		result.append(current)
		
		var neighbors = hex_grid.get_neighbors(current)
		for neighbor in neighbors:
			if visited.get(neighbor, false):
				continue
			
			var owner = hex_grid.territory_map.get(neighbor, 0)
			if owner == owner_team:
				visited[neighbor] = true
				queue.append(neighbor)
	
	return result

func calculate_center(hexes: Array) -> Vector2i:
	"""Oblicza środek grupy hexów"""
	if hexes.is_empty():
		return Vector2i.ZERO
	
	var sum_q = 0
	var sum_r = 0
	for hex in hexes:
		sum_q += hex.x
		sum_r += hex.y
	
	return Vector2i(sum_q / hexes.size(), sum_r / hexes.size())

func evaluate_group_worth(group: Dictionary, state: Dictionary) -> bool:
	"""Ocenia czy warto iść po odłączoną grupę terytoriów"""
	
	# Jeśli niebezpieczne (blisko wroga) i małe - nie warto
	if not group.safe and group.size < 3:
		if DEBUG: print("AI %d: Grupa %d hexów niebezpieczna i mała - SKIP" % [team, group.size])
		return false
	
	# Jeśli duża grupa (6+ hexów) - zawsze warto, nawet jeśli daleko
	if group.size >= 6:
		if DEBUG: print("AI %d: Grupa %d hexów DUŻA - WARTO!" % [team, group.size])
		return true
	
	# Jeśli relatywnie blisko (≤8 pól) i bezpieczna - warto
	if group.distance_to_main <= 8 and group.safe:
		if DEBUG: print("AI %d: Grupa %d hexów blisko i bezpieczna - WARTO!" % [team, group.size])
		return true
	
	# Jeśli bardzo blisko zamku (≤5 pól) - warto dla obrony
	if group.distance_to_castle <= 5:
		if DEBUG: print("AI %d: Grupa %d hexów blisko zamku - WARTO!" % [team, group.size])
		return true
	
	if DEBUG: print("AI %d: Grupa %d hexów - nie warto" % [team, group.size])
	return false

func collect_units(state: Dictionary):
	"""Zbiera wszystkie jednostki z walidacją"""
	
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

func collect_castles_and_camps(state: Dictionary):
	"""Zbiera zamki i obozy bandytów"""
	
	for coords in hex_grid.castle_map:
		var castle = hex_grid.castle_map[coords]
		
		if castle.team == team:
			state.my_castles.append(coords)
			
			# Sprawdź zagrożenia zamku - tylko bezpośrednie (1 hex)
			for enemy in state.enemy_units:
				var dist = hex_distance(enemy.pos, coords)
				if dist <= 1:  # TYLKO bezpośredni sąsiad = realne zagrożenie
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

func analyze_enemy_kingdoms(state: Dictionary) -> Dictionary:
	"""Analizuje siły każdego wrogiego królestwa"""
	var kingdoms = {}
	
	# Zlicz jednostki każdego królestwa
	for enemy in state.enemy_units:
		var enemy_team = enemy.team
		
		if not kingdoms.has(enemy_team):
			kingdoms[enemy_team] = {
				"team": enemy_team,
				"units": [],
				"total_strength": 0,
				"unit_count": 0,
				"distance_to_me": 999999,
				"castle_pos": Vector2i.ZERO,
				"threat_level": 0
			}
		
		kingdoms[enemy_team].units.append(enemy)
		kingdoms[enemy_team].total_strength += enemy.strength
		kingdoms[enemy_team].unit_count += 1
	
	# Znajdź zamki i odległości
	for castle_pos in state.enemy_castles:
		var castle = hex_grid.castle_map[castle_pos]
		var enemy_team = castle.team
		
		if kingdoms.has(enemy_team):
			kingdoms[enemy_team].castle_pos = castle_pos
			
			# Odległość do mojego królestwa
			if not state.my_castles.is_empty():
				var dist = hex_distance(castle_pos, state.my_castles[0])
				kingdoms[enemy_team].distance_to_me = dist
	
	# Oceń poziom zagrożenia
	for team_id in kingdoms:
		var kingdom = kingdoms[team_id]
		kingdom.threat_level = calculate_threat_level(kingdom, state)
	
	return kingdoms

func calculate_threat_level(kingdom: Dictionary, state: Dictionary) -> float:
	"""Oblicza poziom zagrożenia od danego królestwa"""
	var threat = 0.0
	
	# Im bliżej, tym większe zagrożenie
	if kingdom.distance_to_me <= 5:
		threat += 100.0
	elif kingdom.distance_to_me <= 10:
		threat += 50.0
	else:
		threat += 10.0
	
	# Im silniejsze, tym większe zagrożenie
	threat += kingdom.total_strength * 0.5
	
	# Bonus za liczność
	threat += kingdom.unit_count * 10
	
	return threat

# ============================================================================
# STRATEGY DECISION
# ============================================================================

func decide_strategy(state: Dictionary):
	"""Decyduje o strategii na turę"""
	
	if DEBUG: print("AI %d: === DECYZJA STRATEGICZNA ===" % team)
	
	# PRIORYTET 1: Obrona zamku
	if memory.castle_under_attack:
		current_strategy = Strategy.DEFENSIVE
		if DEBUG: print("AI %d: STRATEGIA -> DEFENSIVE (zamek zagrożony)" % team)
		return
	
	# PRIORYTET 2: Połączenie z zamkiem sojusznika (ten sam kolor)
	if state.has("ally_castles_to_connect") and not state.ally_castles_to_connect.is_empty():
		var nearest_ally = state.ally_castles_to_connect[0]
		if nearest_ally.distance <= 12:  # Wystarczająco blisko
			current_strategy = Strategy.EXPANSION
			if DEBUG: print("AI %d: STRATEGIA -> EXPANSION (łączenie z zamkiem sojusznika #%d, dist: %d)" % [team, nearest_ally.kingdom_id, nearest_ally.distance])
			# Ustaw cel ekspansji w kierunku zamku sojusznika
			memory.expansion_targets = [{"center": nearest_ally.castle_pos, "worth_connecting": true, "hexes": [], "size": 1}]
			return
	
	# PRIORYTET 3: Połączenie odłączonych terytoriów
	var worthy_groups = []
	for group in state.my_detached_groups:
		if group.worth_connecting:
			worthy_groups.append(group)
	
	if worthy_groups.size() > 0:
		current_strategy = Strategy.EXPANSION
		if DEBUG: print("AI %d: STRATEGIA -> EXPANSION (odłączone terytoria: %d)" % [team, worthy_groups.size()])
		memory.expansion_targets = worthy_groups
		return
	
	# PRIORYTET 3: Obozy bandytów w pobliżu (BARDZO OPŁACALNE - +10 gold + usuwa bandytów!)
	# Bandyci okupują pola i blokują dochody - muszą być TOP priorytetem
	var nearby_camps = []
	for camp_pos in state.bandit_camps:
		var dist = get_min_unit_distance_to(camp_pos, state.my_units)
		if dist <= 9:  # Zwiększony zasięg z 7 do 9 - bardzo agresywne
			nearby_camps.append(camp_pos)
	
	if nearby_camps.size() > 0:
		current_strategy = Strategy.OPPORTUNISTIC
		if DEBUG: print("AI %d: STRATEGIA -> OPPORTUNISTIC (obozy bandytów: %d - KRYTYCZNE!)" % [team, nearby_camps.size()])
		return
	
	# PRIORYTET 4: Atak na słabe królestwo
	var my_strength = calculate_my_strength(state)
	var attackable_kingdom = find_attackable_kingdom(state, my_strength)
	
	if not attackable_kingdom.is_empty():
		current_strategy = Strategy.AGGRESSIVE
		if DEBUG: print("AI %d: STRATEGIA -> AGGRESSIVE (cel: Team %d)" % [team, attackable_kingdom.team])
		return
	
	# DOMYŚLNIE: Ekspansja
	current_strategy = Strategy.EXPANSION
	if DEBUG: print("AI %d: STRATEGIA -> EXPANSION (domyślna)" % team)

func calculate_my_strength(state: Dictionary) -> Dictionary:
	"""Oblicza moją siłę bojową"""
	var strength = {
		"total": 0,
		"unit_count": 0,
		"gold": state.gold,
		"knights": 0,
		"cavalry": 0,
		"spearmen": 0,
		"farmers": 0
	}
	
	for unit in state.my_units:
		strength.total += unit.strength
		strength.unit_count += 1
		
		if unit.type == "knight":
			strength.knights += 1
		elif unit.type == "cavalry":
			strength.cavalry += 1
		elif unit.type == "spearman":
			strength.spearmen += 1
		elif unit.type == "farmer":
			strength.farmers += 1
	
	return strength

func find_attackable_kingdom(state: Dictionary, my_strength: Dictionary) -> Dictionary:
	"""Znajduje królestwo które możemy zaatakować"""
	
	for team_id in state.enemy_kingdoms:
		var kingdom = state.enemy_kingdoms[team_id]
		
		# Jeśli jesteśmy ogólnie silniejsi
		if my_strength.total > kingdom.total_strength * 1.2:
			# I królestwo jest relatywnie blisko
			if kingdom.distance_to_me <= 8:
				if DEBUG: print("AI %d: Znaleziono cel: Team %d (siła: %d vs moja: %d)" % [team, team_id, kingdom.total_strength, my_strength.total])
				return kingdom
	
	return {}

# ============================================================================
# STRATEGIC GOALS
# ============================================================================

func set_strategic_goals(state: Dictionary):
	strategic_goals.clear()
	
	# PRIORYTET #0: ELIMINACJA WROGÓW W ZASIĘGU 1
	# Spearman/knight/cavalry który SĄSIADUJE z wrogiem ZAWSZE go atakuje zamiast iść dalej
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		if unit_data.type not in ["knight", "cavalry", "spearman"]:
			continue
		
		var attacker_pos = unit_data.unit.hex_position
		var moves = get_possible_moves(unit_data.type, attacker_pos)
		
		for move_pos in moves:
			# Sprawdź czy na tym polu jest wroga jednostka
			var target_unit = null
			var target_type = ""
			if hex_grid.knight_map.has(move_pos):
				var k = hex_grid.knight_map[move_pos]
				if is_instance_valid(k) and k.team != team and k.team > 0:
					target_unit = k
					target_type = "knight"
			elif hex_grid.cavalry_map.has(move_pos):
				var c = hex_grid.cavalry_map[move_pos]
				if is_instance_valid(c) and c.team != team and c.team > 0:
					if unit_data.type in ["cavalry", "knight"]:
						target_unit = c
						target_type = "cavalry"
			elif unit_data.type == "spearman" and hex_grid.farmer_map.has(move_pos):
				var f = hex_grid.farmer_map[move_pos]
				if is_instance_valid(f) and f.team != team and f.team > 0 and f.team != -1:
					target_unit = f
					target_type = "farmer"
			elif unit_data.type == "spearman" and hex_grid.spearman_map.has(move_pos):
				var s = hex_grid.spearman_map[move_pos]
				if is_instance_valid(s) and s.team != team and s.team > 0:
					target_unit = s
					target_type = "spearman"
			
			if target_unit != null:
				# Upewnij się że knight nie atakuje cavalry (niemożliwe mechanicznie)
				if unit_data.type == "knight" and target_type == "cavalry":
					continue
				
				# Priorytet zależy od siły celu i atakującego
				var priority = 430  # Wysoki priorytet - wyższy niż capture_castle
				if unit_data.type == "spearman" and target_type in ["farmer", "spearman"]:
					priority = 420  # Trochę niższy niż knight eliminacja, ale wyżej niż zamek
				strategic_goals.append({
					"type": "eliminate_high_value_target",
					"attacker": unit_data,
					"attacker_pos": attacker_pos,
					"target_pos": move_pos,
					"target_type": target_type,
					"priority": priority
				})
				if DEBUG: print("AI %d: 🎯 WYKRYTO CEL ELIMINACJI: %s @ %s może zabić %s @ %s (priorytet: %d)" % [team, unit_data.type, attacker_pos, target_type, move_pos, priority])
				break  # Jedna eliminacja per jednostka
	
	# PRIORYTET #0: OCHRONA PRZED ODCIĘCIEM (bardzo wysoki!)
	if state.has("cutoff_threats") and not state.cutoff_threats.is_empty():
		for threat in state.cutoff_threats:
			strategic_goals.append({
				"type": "defend_from_cutoff",
				"threat_data": threat,
				"priority": 350,  # Wyższy niż większość celów
			})
	
	# PRIORYTET #0b: PROAKTYWNE WZMACNIANIE WĄSKICH GARDEŁ
	# Znajdź własne pola z jednostkami które mają <=2 połączenia z własnym terytorium
	# i wróg jest blisko - postaw mury zanim zostaniemy odcięci
	var gold_for_walls = hex_grid.get_selected_kingdom_gold(team)
	if gold_for_walls >= hex_grid.WALL_COST_PER_HEX:
		var bottleneck_candidates = []
		for unit_data in state.my_units:
			if not is_instance_valid(unit_data.unit):
				continue
			var upos = unit_data.unit.hex_position
			# Policz ile sąsiadów to własne terytorium
			var own_neighbors = 0
			for nb in hex_grid.get_neighbors(upos):
				if hex_grid.territory_map.get(nb, 0) == team:
					own_neighbors += 1
			# Sprawdź czy wróg jest blisko (dystans <= 3)
			var enemy_close = false
			for enemy in state.enemy_units:
				if hex_distance(upos, enemy.pos) <= 3:
					enemy_close = true
					break
			if own_neighbors <= 2 and enemy_close:
				# To jest wąskie gardło zagrożone wrogiem
				# Znajdź najlepszy hex do umocnienia (sąsiad z jednym połączeniem do nas)
				for nb in hex_grid.get_neighbors(upos):
					if hex_grid.territory_map.get(nb, 0) == team:
						var walls_there = count_walls_around(nb)
						if walls_there < 6 and not hex_grid.castle_map.has(nb):
							bottleneck_candidates.append({
								"pos": nb,
								"unit_pos": upos,
								"unit_type": unit_data.type
							})
		if not bottleneck_candidates.is_empty():
			strategic_goals.append({
				"type": "fortify_bottleneck",
				"candidates": bottleneck_candidates,
				"priority": 340  # Wysoki ale poniżej aktywnej obrony
			})
	
	# PRIORYTET #1: ODCINANIE JEDNOSTEK (NAJWAŻNIEJSZE - KLUCZ DO WYGRANEJ!)
	for opp in state.cutoff_opportunities:
		# Zwiększ priorytet jeszcze bardziej!
		var boosted_priority = opp.priority + 100  # 300-500!
		strategic_goals.append({
			"type": "surround_enemy",
			"data": opp,
			"priority": boosted_priority
		})
	
	# PRIORYTET #2: Obrona zamku - TYLKO NAGŁY WYPADEK (wróg 1 hex od zamku!)
	# Normalna obrona = odcięcie lub mury, nie cofanie jednostek
	if not state.castle_threats.is_empty():
		for threat in state.castle_threats:
			if threat.distance <= 1:  # TYLKO bezpośredni sąsiad zamku!
				strategic_goals.append({
					"type": "defend_castle",
					"castle_pos": threat.castle_pos,
					"enemy_pos": threat.enemy.pos,
					"priority": 300,
				})
	
	# PRIORYTET #3: Połączenie odłączonych terytoriów
	if current_strategy == Strategy.EXPANSION and memory.expansion_targets.size() > 0:
		for group in memory.expansion_targets:
			strategic_goals.append({
				"type": "connect_territory",
				"target_group": group,
				"priority": 250,
			})
	
	# PRIORYTET #3: Zdobycie zamków BLISKO (bardzo wysoki priorytet!)
	for castle_pos in state.undefended_enemy_castles:
		var distance = get_min_unit_distance_to(castle_pos, state.my_units)
		
		# NOWE: Sprawdź czy zamek ma JAKIEKOLWIEK jednostki w promieniu 3
		var castle_team = hex_grid.castle_map[castle_pos].team
		var has_any_defenders = false
		var range3_hexes = get_hexes_in_range_manual(castle_pos, 3)
		for hex_pos in range3_hexes:
			if hex_grid.knight_map.has(hex_pos) and hex_grid.knight_map[hex_pos].team == castle_team:
				has_any_defenders = true
				break
			if hex_grid.spearman_map.has(hex_pos) and hex_grid.spearman_map[hex_pos].team == castle_team:
				has_any_defenders = true
				break
			if hex_grid.cavalry_map.has(hex_pos) and hex_grid.cavalry_map[hex_pos].team == castle_team:
				has_any_defenders = true
				break
		
		var priority = 0
		if not has_any_defenders:
			# CAŁKOWICIE BEZBRONNY ZAMEK - NATYCHMIASTOWY ATAK! (najwyższy priorytet)
			priority = 400 - distance * 5  # 350-400 (wyższe niż defend_from_cutoff)
			if DEBUG: print("AI %d: ⚠️ WYKRYTO BEZBRONNY ZAMEK @ %s (dystans: %d, priorytet: %d)" % [team, castle_pos, distance, priority])
		elif distance <= 3:
			# BLISKO - wysoki priorytet
			priority = 280 - distance * 20  # 220-280
		
		if priority > 0:
			var my_castle_pos = state.my_castles[0] if not state.my_castles.is_empty() else Vector2i.ZERO
			if my_castle_pos == Vector2i.ZERO or is_castle_reachable(my_castle_pos, castle_pos):
				strategic_goals.append({
					"type": "capture_castle",
					"position": castle_pos,
					"priority": priority,
					"target_team": castle_team,
					"distance": distance,
					"defenseless": not has_any_defenders
				})
			else:
				if DEBUG: print("AI %d: Zamek %s nieosiągalny - pomijam cel" % [team, castle_pos])
	
	for castle_pos in state.walled_enemy_castles:
		var distance = get_min_unit_distance_to(castle_pos, state.my_units)
		if distance <= 2:  # Tylko jeśli BARDZO BLISKO (mury trudniejsze)
			var priority = 150 - distance * 20
			
			strategic_goals.append({
				"type": "capture_walled_castle",
				"position": castle_pos,
				"priority": priority,
				"target_team": hex_grid.castle_map[castle_pos].team,
				"distance": distance
			})
	
	# PRIORYTET #4: Obozy bandytów (+10 GOLD + usuwa wszystkich bandytów - KRYTYCZNE!)
	# Bandyci okupują pola i blokują dochód - obozy MUSZĄ być TOP priorytetem gdy blisko!
	for camp_pos in state.bandit_camps:
		var distance = get_min_unit_distance_to(camp_pos, state.my_units)
		if distance <= 8:  # Zasięg wykrywania
			# EKSTREMALNIE wysoki priorytet gdy BARDZO blisko (1-2 pola)
			var priority = 400  # Bazowy BARDZO wysoki
			if distance == 1:
				priority = 450  # NATYCHMIASTOWY PRIORYTET - wyższy niż wszystko!
			elif distance == 2:
				priority = 420  # Bardzo wysoki
			elif distance == 3:
				priority = 380  # Wysoki
			elif distance <= 5:
				priority = 340 - (distance - 3) * 10  # 340, 330, 320
			else:
				priority = 290 - (distance - 5) * 10  # 280, 270, 260
			
			strategic_goals.append({
				"type": "capture_bandit_camp",
				"position": camp_pos,
				"priority": priority,
				"distance": distance,  # Dla debugowania
			})
	
	# PRIORYTET #5: Ekspansja wokół zamku (obrona)
	if not state.my_castles.is_empty():
		strategic_goals.append({
			"type": "expand_around_castle",
			"priority": 40
		})
	
	# ZAWSZE dodaj ekspansję jako fallback
	strategic_goals.append({
		"type": "expand_territory",
		"priority": 10
	})
	
	strategic_goals.sort_custom(func(a, b): return a.priority > b.priority)
	
	if DEBUG: print("AI %d: Cele strategiczne:" % team)
	for goal in strategic_goals:
		if DEBUG: print("  - %s (priorytet: %d)" % [goal.type, goal.priority])

# ============================================================================
# CUTOFF OPPORTUNITIES
# ============================================================================

func find_cutoff_opportunities(state: Dictionary) -> Array:
	"""Znajduje możliwości odcięcia wrogich jednostek - z KOORDYNACJĄ"""
	var opportunities = []
	
	if DEBUG: print("AI %d: Sprawdzam możliwości odcięcia dla %d wrogich jednostek" % [team, state.enemy_units.size()])
	
	# Dla każdej wrogiej jednostki
	for enemy in state.enemy_units:
		if not enemy.has("team") or not is_instance_valid(enemy.unit):
			continue
		
		var enemy_pos = enemy.pos
		var enemy_team = enemy.team
		
		if DEBUG: print("AI %d: Analizuję wroga %s na %s (team: %d)" % [team, enemy.type, enemy_pos, enemy_team])
		
		# Znajdź pola wokół wroga
		var neighbors = hex_grid.get_neighbors(enemy_pos)
		var enemy_territory_connections = []  # POZYCJE połączeń wroga
		var fields_to_capture = []  # Pola które MUSIMY zająć (przy połączeniach)
		
		for neighbor in neighbors:
			var owner = hex_grid.territory_map.get(neighbor, 0)
			
			# Zapisz połączenia wroga z własnym terytorium
			if owner == enemy_team:
				enemy_territory_connections.append(neighbor)
		
		if DEBUG: print("AI %d: Wróg %s - połączenia: %d na polach: %s" % [team, enemy.type, enemy_territory_connections.size(), enemy_territory_connections])
		
		# Odcinanie ma sens tylko jeśli wróg ma ≤2 połączenia
		if enemy_territory_connections.size() <= 2 and enemy_territory_connections.size() > 0:
			# KLUCZOWE: Musimy zająć TYLKO pola OBOK tych połączeń, nie wszystkie puste pola!
			
			# Dla każdego połączenia wroga, znajdź pola które możemy zająć żeby je odciąć
			for connection in enemy_territory_connections:
				var connection_neighbors = hex_grid.get_neighbors(connection)
				
				for conn_neighbor in connection_neighbors:
					# Pomijamy samego wroga
					if conn_neighbor == enemy_pos:
						continue
					
					var owner = hex_grid.territory_map.get(conn_neighbor, 0)
					var hex = hex_grid.get_hex_at(conn_neighbor)
					
					# Pole które możemy zająć (nasze lub neutralne)
					if (owner == team or owner == 0) and hex:
						# Puste pole - możemy je zająć
						if hex.occupied_object == null:
							# Dodaj tylko jeśli jeszcze nie ma na liście
							var already_added = false
							for field in fields_to_capture:
								if field.pos == conn_neighbor:
									already_added = true
									break
							
							if not already_added:
								fields_to_capture.append({
									"pos": conn_neighbor,
									"blocks_connection": connection
								})
						# Pole z naszą jednostką - możemy przeskoczyć
						elif has_team(hex.occupied_object) and hex.occupied_object.team == team:
							# Już blokujemy to połączenie!
							pass
			
			if DEBUG: print("AI %d: Pól do zajęcia (przy połączeniach): %d" % [team, fields_to_capture.size()])
			
			if fields_to_capture.size() >= 1:
				# Ile jednostek RZECZYWIŚCIE potrzebujemy?
				# Jeśli wróg ma 1 połączenie - wystarczy 1 jednostka
				# Jeśli wróg ma 2 połączenia - wystarczą 2 jednostki
				var units_needed = min(fields_to_capture.size(), enemy_territory_connections.size())
				
				if DEBUG: print("AI %d: Możliwe odcięcie! Wróg ma %d połączenia, potrzeba %d jednostek (pól dostępnych: %d)" % 
					[team, enemy_territory_connections.size(), units_needed, fields_to_capture.size()])
				
				# Znajdź jednostki które mogą pomóc
				var available_units = []
				for unit_data in state.my_units:
					if not is_instance_valid(unit_data.unit):
						continue
					
					# Pomiń już ruszone jednostki
					if unit_data.unit in hex_grid.units_moved_this_turn:
						continue
					
					# Użyj aktualnej pozycji jednostki (nie cached z początku tury)
					var current_pos = unit_data.unit.hex_position
					
					# Jednostka musi być w zasięgu ruchu do któregoś z pól
					for field in fields_to_capture:
						var moves = get_possible_moves(unit_data.type, current_pos)
						
						# Czy może dotrzeć do tego pola?
						if field.pos in moves:
							if unit_data not in available_units:
								available_units.append({
									"unit_data": unit_data,
									"distance_to_enemy": hex_distance(current_pos, enemy_pos)
								})
							break
				
				if DEBUG: print("AI %d: Dostępne jednostki: %d" % [team, available_units.size()])
				
				# Sprawdź czy mamy wystarczająco jednostek
				var can_execute = false
				var can_buy_missing = false
				var missing_units = 0
				
				if available_units.size() >= units_needed:
					can_execute = true
					if DEBUG: print("AI %d: ✓ Mamy wystarczająco jednostek!" % team)
				else:
					# Sprawdź czy możemy dokupić brakujące jednostki
					missing_units = units_needed - available_units.size()
					var cost = missing_units * hex_grid.FARMER_COST
					
					if DEBUG: print("AI %d: Brakuje %d jednostek, koszt: %d, mamy złota: %d" % [team, missing_units, cost, state.gold])
					
					if state.gold >= cost:
						can_buy_missing = true
						can_execute = true
						if DEBUG: print("AI %d: ✓ Możemy dokupić!" % team)
				
				if can_execute:
					# Sortuj jednostki według odległości do wroga
					available_units.sort_custom(func(a, b): 
						return a.distance_to_enemy < b.distance_to_enemy
					)
					
					# Buduj sekwencję ruchów
					var sequence = []
					var assigned_units = []
					
					# Sortuj pola według odległości od wroga
					fields_to_capture.sort_custom(func(a, b):
						return hex_distance(a.pos, enemy_pos) < hex_distance(b.pos, enemy_pos)
					)
					
					var priority = 1
					# Przypisz jednostki do PIERWSZYCH units_needed pól
					for i in range(min(units_needed, fields_to_capture.size())):
						var field = fields_to_capture[i]
						
						# Znajdź najlepszą NIEPRZYPISANĄ jednostkę
						var best_unit = null
						var best_score = -999999
						
						for unit_info in available_units:
							var unit_data = unit_info.unit_data
							
							if unit_data in assigned_units:
								continue
							
							var dist_to_field = hex_distance(unit_data.pos, field.pos)
							var score = 100 - dist_to_field
							
							var dist_to_enemy = hex_distance(unit_data.pos, enemy_pos)
							score += dist_to_enemy * 5
							
							if score > best_score:
								best_score = score
								best_unit = unit_data
						
						if best_unit:
							sequence.append({
								"unit": best_unit,
								"target": field.pos,
								"priority": priority
							})
							assigned_units.append(best_unit)
							priority += 1
					
					# Oblicz końcowy priorytet
					var opp_priority = 200 + enemy.strength
					if enemy.type == "cavalry":
						opp_priority += 100
					elif enemy.type == "knight":
						opp_priority += 50
					
					opportunities.append({
						"type": "cutoff",
						"enemy": enemy,
						"bottleneck_hex": enemy_pos,
						"units_to_use": assigned_units,
						"move_sequence": sequence,
						"priority": opp_priority,
						"enemy_connections": enemy_territory_connections.size(),
						"can_buy_missing": can_buy_missing,
						"missing_units": missing_units
					})
					
					if DEBUG: print("AI %d: ✓ ZNALEZIONO ODCIĘCIE! Wróg %s na %s, połączeń: %d, potrzeba: %d jednostek (mamy: %d%s), priorytet: %d" % 
						[team, enemy.type, enemy_pos, enemy_territory_connections.size(), units_needed, assigned_units.size(), 
						(" +%d dokup" % missing_units) if can_buy_missing else "", opp_priority])
				else:
					if DEBUG: print("AI %d: Nie można odciąć - brak jednostek i złota" % team)
			else:
				if DEBUG: print("AI %d: Pominięto - brak pól do zajęcia przy połączeniach" % team)
		else:
			if enemy_territory_connections.size() > 2:
				if DEBUG: print("AI %d: Pominięto - za dużo połączeń (%d)" % [team, enemy_territory_connections.size()])
			else:
				if DEBUG: print("AI %d: Pominięto - wróg nie ma połączeń z własnym terytorium (już otoczony?)" % team)
	
	if DEBUG: print("AI %d: Znaleziono %d możliwości odcięcia" % [team, opportunities.size()])
	return opportunities

func find_narrowest_point_on_path(path: Array, owner_team: int, state: Dictionary) -> Dictionary:
	"""Znajduje najwęższy punkt na ścieżce wroga - gdzie najmniej połączeń"""
	
	var narrowest_width = 999999
	var narrowest_hex = null
	var narrowest_index = -1
	
	# Sprawdź każde pole na ścieżce (pomijając start i koniec)
	for i in range(1, path.size() - 1):
		var hex_pos = path[i]
		
		# Zlicz ile sąsiadów tego samego teamu
		var friendly_connections = count_friendly_neighbors(hex_pos, owner_team)
		
		# Im mniej połączeń, tym węższe gardło
		if friendly_connections < narrowest_width:
			narrowest_width = friendly_connections
			narrowest_hex = hex_pos
			narrowest_index = i
	
	if narrowest_hex == null:
		return {}
	
	# Znajdź sąsiednie pola które możemy zająć aby odciąć
	var neighbors = hex_grid.get_neighbors(narrowest_hex)
	var capturable_neighbors = []
	
	for neighbor in neighbors:
		var owner = hex_grid.territory_map.get(neighbor, 0)
		var hex = hex_grid.get_hex_at(neighbor)
		
		# Możemy zająć jeśli NIE należy do wroga lub jest puste
		if hex and (owner != owner_team or owner == 0):
			if hex.occupied_object == null:
				capturable_neighbors.append(neighbor)
	
	if capturable_neighbors.is_empty():
		return {}
	
	return {
		"hex": narrowest_hex,
		"width": narrowest_width,
		"capturable_neighbors": capturable_neighbors,
		"path_index": narrowest_index
	}

func plan_cutoff_coordination(bottleneck_data: Dictionary, enemy: Dictionary, state: Dictionary) -> Dictionary:
	"""Planuje koordynację jednostek do odcięcia - SEKWENCYJNIE"""
	
	var result = {
		"can_execute": false,
		"units": [],
		"sequence": []  # Kolejność ruchów
	}
	
	var target_hex = bottleneck_data.hex
	var capturable = bottleneck_data.capturable_neighbors
	
	# Ile jednostek potrzeba? (przynajmniej tyle by zająć wąskie gardło + sąsiadów)
	var units_needed = min(capturable.size() + 1, 3)  # Max 3 jednostki
	
	# Znajdź nasze jednostki które mogą dojść
	var available_units = []
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		
		# Oblicz dystans do celu
		var dist_to_target = hex_distance(unit_data.pos, target_hex)
		
		# Jednostki w zasięgu 5 pól mogą pomóc
		if dist_to_target <= 5:
			available_units.append({
				"unit": unit_data,
				"distance": dist_to_target,
				"can_attack": unit_data.type in ["knight", "spearman", "cavalry"]
			})
	
	if available_units.size() < units_needed:
		# Za mało jednostek - sprawdź czy możemy dokupić
		var missing = units_needed - available_units.size()
		if missing <= 2 and state.gold >= missing * hex_grid.FARMER_COST:
			result.can_buy_units = true
			result.units_to_buy = missing
		else:
			return result  # Nie możemy wykonać
	
	# Sortuj według odległości i siły
	available_units.sort_custom(func(a, b):
		# Najpierw bojowe, potem bliżej
		if a.can_attack != b.can_attack:
			return a.can_attack
		return a.distance < b.distance
	)
	
	# Wybierz jednostki
	var selected_units = []
	for i in range(min(units_needed, available_units.size())):
		selected_units.append(available_units[i].unit)
	
	# KLUCZOWE: Zaplanuj SEKWENCJĘ ruchów
	# 1. Najpierw silniejsze jednostki (knight) idą na główne pole
	# 2. Potem słabsze (farmer) blokują sąsiadów
	
	var sequence = []
	
	# Faza 1: Knight/Cavalry na główne wąskie gardło
	for unit_data in selected_units:
		if unit_data.type in ["knight", "cavalry"]:
			sequence.append({
				"unit": unit_data,
				"target": target_hex,
				"priority": 1  # Najwyższy priorytet
			})
			break  # Tylko jedna jednostka bojowa na główne pole
	
	# Faza 2: Pozostałe jednostki na sąsiednie pola
	var remaining_targets = capturable.duplicate()
	var seq_priority = 2
	var assigned_units = []  # NOWE: Śledź przypisane jednostki
	
	for target_field in remaining_targets:
		# Znajdź najbliższą NIEPRZYPISAN jednostkę do tego pola
		var best_unit = null
		var min_dist = 999999
		
		for unit_data in selected_units:
			# Pomiń już przypisane
			if unit_data in assigned_units:
				continue
			
			var dist = hex_distance(unit_data.pos, target_field)
			if dist < min_dist:
				min_dist = dist
				best_unit = unit_data
		
		if best_unit != null:
			sequence.append({
				"unit": best_unit,
				"target": target_field,
				"priority": seq_priority
			})
			assigned_units.append(best_unit)  # NOWE: Oznacz jako przypisaną
			seq_priority += 1
	
	result.can_execute = true
	result.units = selected_units
	result.sequence = sequence
	
	return result

func execute_coordinated_cutoff(state: Dictionary, cutoff_data: Dictionary):
	"""WYKONUJE SKOORDYNOWANE ODCIĘCIE - jednostki działają razem w sekwencji"""
	
	var sequence = cutoff_data.move_sequence
	
	if DEBUG: print("AI %d: === KOORDYNOWANE ODCIĘCIE ===" % team)
	if DEBUG: print("AI %d: Cel: %s (siła: %d)" % [team, cutoff_data.enemy.type, cutoff_data.enemy.strength])
	if DEBUG: print("AI %d: Wąskie gardło: %s" % [team, cutoff_data.bottleneck_hex])
	#print("AI %d: Pola do zajęcia: %s" % [team, cutoff_data.capturable_hexes])  # DODANE
	if DEBUG: print("AI %d: Jednostek w sekwencji: %d" % [team, sequence.size()])
	
	# Sortuj według priorytetu (1 = pierwszy, 2 = drugi, itd.)
	sequence.sort_custom(func(a, b): return a.priority < b.priority)
	
	# NOWE: Śledzenie zajętych pól
	var occupied_fields = []
	
	# WYKONUJ RUCHY W KOLEJNOŚCI
	for step in sequence:
		var unit_data = step.unit
		var target = step.target
		
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			if DEBUG: print("AI %d: Jednostka %s już ruszona, pomijam" % [team, unit_data.type])
			continue
		
		# Użyj AKTUALNEJ pozycji jednostki (mogła się ruszyć wcześniej w tej turze)
		var current_pos = unit_data.unit.hex_position
		
		# Znajdź najlepszy ruch w kierunku celu
		var moves = get_possible_moves(unit_data.type, current_pos)
		
		# NOWE: Filtruj pola już zajęte przez nasze jednostki w tej turze
		var available_moves = []
		for move in moves:
			if move not in occupied_fields:
				available_moves.append(move)
		
		if available_moves.is_empty():
			if DEBUG: print("AI %d: UWAGA! %s nie ma dostępnych ruchów (wszystkie zajęte)" % [team, unit_data.type])
			continue
		
		if target in available_moves:
			# POPRAWKA: Idź bezpośrednio na cel!
			if DEBUG: print("AI %d: [PRIORYTET %d] %s -> %s (BEZPOŚREDNIO!)" % [team, step.priority, unit_data.type, target])
			await execute_move(unit_data.unit, unit_data, target)
			occupied_fields.append(target)  # NOWE: Oznacz jako zajęte
		else:
			# Idź w kierunku celu (tylko jeśli nie możemy bezpośrednio)
			var best_move = find_move_towards_target(current_pos, available_moves, target)
			
			if best_move != Vector2i.ZERO:
				if DEBUG: print("AI %d: [PRIORYTET %d] %s -> %s (krok w kierunku: %s)" % [team, step.priority, unit_data.type, best_move, target])
				await execute_move(unit_data.unit, unit_data, best_move)
				occupied_fields.append(best_move)  # NOWE: Oznacz jako zajęte
			else:
				if DEBUG: print("AI %d: UWAGA! %s nie może dojść do %s" % [team, unit_data.type, target])
	
	if DEBUG: print("AI %d: === KONIEC KOORDYNACJI ===" % team)

func find_path_through_territory(from: Vector2i, to: Vector2i, owner_team: int) -> Array:
	"""Znajduje ścieżkę przez terytorium danego teamu"""
	var visited = {}
	var queue = [[from]]
	visited[from] = true
	
	while not queue.is_empty():
		var path = queue.pop_front()
		var current = path[-1]
		
		if current == to:
			return path
		
		var neighbors = hex_grid.get_neighbors(current)
		for neighbor in neighbors:
			if visited.get(neighbor, false):
				continue
			
			var owner = hex_grid.territory_map.get(neighbor, 0)
			if owner == owner_team or neighbor == to:
				visited[neighbor] = true
				var new_path = path.duplicate()
				new_path.append(neighbor)
				queue.append(new_path)
	
	return []

func count_friendly_neighbors(hex_pos: Vector2i, owner_team: int) -> int:
	"""Zlicza sąsiadów tego samego teamu"""
	var count = 0
	var neighbors = hex_grid.get_neighbors(hex_pos)
	
	for neighbor in neighbors:
		var owner = hex_grid.territory_map.get(neighbor, 0)
		if owner == owner_team:
			count += 1
	
	return count

func evaluate_move_cutoff_risk(unit_data: Dictionary, target_pos: Vector2i, state: Dictionary) -> Dictionary:
	"""Przewiduje o 1 krok: czy po ruchu na target_pos nasza jednostka zostanie odcięta przez wroga?
	   Zwraca:
	   {
		 "risk": bool,            # Czy jest ryzyko odcięcia
		 "risk_level": float,     # 0.0 (brak) - 1.0 (pewne odcięcie)
		 "worth_it": bool,        # Czy warto mimo ryzyka (np. farmer odcina cavalry)
		 "blockers": Array,       # Wrogie jednostki mogące odciąć
		 "reason": String
	   }
	"""
	var result = {
		"risk": false,
		"risk_level": 0.0,
		"worth_it": true,
		"blockers": [],
		"reason": "brak ryzyka"
	}
	
	# Symuluj: po ruchu unit stoi na target_pos
	# Sprawdź ile połączeń z własnym terytorium będzie mieć na tej pozycji
	var connections_after = 0
	var connection_points = []
	
	for neighbor in hex_grid.get_neighbors(target_pos):
		var owner = hex_grid.territory_map.get(neighbor, 0)
		# Po ruchu: jeśli neighbor to stara pozycja jednostki, już nie będzie naszym polem
		# (ale pole nie zmienia właściciela - tylko unit się rusza, więc teren pozostaje)
		if owner == team:
			connections_after += 1
			connection_points.append(neighbor)
		# Jeśli idziemy na wrogie pole - przejmujemy je, więc target_pos staje się nasze
		# ale sąsiedzi pozostają bez zmian
	
	# Jeśli mamy >=3 połączeń po ruchu - bezpieczne
	if connections_after >= 3:
		result.reason = "bezpieczna pozycja (%d połączeń)" % connections_after
		return result
	
	# Sprawdź czy wrogowie mogą w następnym ruchu zająć punkty połączenia
	var potential_blockers = []
	
	for conn_point in connection_points:
		# Wróg może zająć conn_point jeśli stoi w sąsiedztwie i to pole jest osiągalne
		var conn_neighbors = hex_grid.get_neighbors(conn_point)
		for cn in conn_neighbors:
			if cn == target_pos:
				continue  # Pomijamy cel ruchu
			# Sprawdź czy stoi tam wrogi farmer/spearman/knight/cavalry
			for enemy in state.enemy_units:
				if enemy.pos == cn:
					var moves = get_possible_moves(enemy.type, cn)
					if conn_point in moves:
						# Ten wróg może zająć nasz punkt połączenia!
						var already_added = false
						for b in potential_blockers:
							if b.enemy.pos == enemy.pos and b.target == conn_point:
								already_added = true
								break
						if not already_added:
							potential_blockers.append({
								"enemy": enemy,
								"target": conn_point
							})
	
	if potential_blockers.is_empty():
		result.reason = "wrogowie nie mogą odciąć (%d połączeń)" % connections_after
		return result
	
	# Jest ryzyko - oceń poziom
	result.risk = true
	result.blockers = potential_blockers
	
	# risk_level zależy od: liczby połączeń i liczby wrogów mogących odciąć
	var max_cutters = potential_blockers.size()
	if connections_after == 1:
		result.risk_level = 1.0  # Pewne odcięcie jeśli wróg zaatakuje jedyne połączenie
	elif connections_after == 2:
		result.risk_level = clamp(0.4 + max_cutters * 0.2, 0.0, 1.0)
	else:
		result.risk_level = clamp(max_cutters * 0.15, 0.0, 0.5)
	
	result.reason = "ryzyko odcięcia (połączeń: %d, blokerów: %d, poziom: %.1f)" % [connections_after, max_cutters, result.risk_level]
	
	# Oceń czy warto mimo ryzyka
	var unit_value = unit_data.strength  # farmer=10, spearman=20, knight=40, cavalry=80
	
	# Co zyskujemy ruszając w to miejsce?
	# - Czy przejmujemy silną wrogą jednostkę / zamek / obóz bandytów?
	var gain_value = 0
	var target_hex = hex_grid.get_hex_at(target_pos)
	if target_hex and target_hex.occupied_object != null:
		var obj = target_hex.occupied_object
		if obj.has_method("get") and obj.get("team") != team:
			if obj.has_meta("camp_id"):
				gain_value = 50  # Obóz bandytów
			elif hex_grid.knight_map.has(target_pos):
				gain_value = 40
			elif hex_grid.cavalry_map.has(target_pos):
				gain_value = 80
			elif hex_grid.spearman_map.has(target_pos):
				gain_value = 20
			elif hex_grid.farmer_map.has(target_pos):
				gain_value = 10
			elif hex_grid.castle_map.has(target_pos):
				gain_value = 100  # Zamek = bardzo cenny
	
	# Zysk z terenu
	gain_value += 5  # Podstawowy zysk za pole
	
	# Policz siłę potencjalnych blokerów
	var blocker_strength = 0
	var blocker_types = {}
	for b in potential_blockers:
		blocker_strength += b.enemy.strength
		blocker_types[b.enemy.type] = true
	
	# Wartość oczekiwana straty = unit_value * risk_level
	var expected_loss = unit_value * result.risk_level
	
	# Warto jeśli zysk > oczekiwana strata LUB jeśli jednostka jest farmerem (tania)
	if unit_data.type == "farmer":
		# Farmer jest tani - warto ryzykować jeśli odcina coś wartościowego
		result.worth_it = gain_value >= 8 or result.risk_level < 0.7
		result.reason += " | farmer: worth=%s (gain=%d, risk=%.1f)" % [result.worth_it, gain_value, result.risk_level]
	elif gain_value >= expected_loss * 1.5:
		# Zysk znacznie przewyższa oczekiwaną stratę
		result.worth_it = true
		result.reason += " | zysk %.1f > strata %.1f → WARTO" % [gain_value, expected_loss]
	elif result.risk_level >= 0.8 and unit_value >= 40:
		# Duże ryzyko odcięcia silnej jednostki - NIE WARTO
		result.worth_it = false
		result.reason += " | ZBYT RYZYKOWNE (knight/cavalry w pułapce)"
	else:
		result.worth_it = gain_value > expected_loss * 0.8
		result.reason += " | bilans: gain=%d, loss_exp=%.1f → %s" % [gain_value, expected_loss, "WARTO" if result.worth_it else "NIE WARTO"]
	
	return result


func find_safe_alternative_move(unit_data: Dictionary, risky_target: Vector2i, state: Dictionary) -> Vector2i:
	"""Szuka alternatywnego bezpiecznego ruchu gdy cel jest zbyt ryzykowny.
	   Priorytet: zablokowanie punktu odcięcia wroga, potem ekspansja bez ryzyka.
	"""
	var current_pos = unit_data.unit.hex_position if is_instance_valid(unit_data.unit) else unit_data.pos
	var possible_moves = get_possible_moves(unit_data.type, current_pos)
	
	var best_move = Vector2i.ZERO
	var best_score = -999999
	
	for move in possible_moves:
		if move == risky_target:
			continue
		
		# Sprawdź bezpieczeństwo tej pozycji
		var risk = evaluate_move_cutoff_risk(unit_data, move, state)
		if risk.risk_level >= 0.7:
			continue  # Ta pozycja też jest ryzykowna
		
		var score = 0
		var owner = hex_grid.territory_map.get(move, 0)
		
		# Bonus za zajmowanie neutralnych/wrogich pól
		if owner == 0:
			score += 10
		elif owner > 0 and owner != team:
			score += 15
		elif owner == team:
			score += 2  # Mało za chodzenie po własnym
		
		# Bonus za bliskość do pierwotnego celu (staramy się być blisko)
		var dist_to_target = hex_distance(move, risky_target)
		score -= dist_to_target * 3
		
		# Bonus za bliskość do zagrożonych punktów połączenia (budujemy "mur")
		for threat in state.get("cutoff_threats", []):
			for vp in threat.vulnerable_points:
				var dist = hex_distance(move, vp.connection_point)
				if dist <= 1:
					score += 30  # Świetna pozycja blokująca
		
		if score > best_score:
			best_score = score
			best_move = move
	
	return best_move


func evaluate_cutoff_worth(cutoff_data: Dictionary, enemy: Dictionary, state: Dictionary) -> bool:
	"""Ocenia czy warto odcinać jednostkę"""
	
	# Ile mamy jednostek w pobliżu?
	var our_nearby = 0
	for unit in state.my_units:
		if hex_distance(unit.pos, cutoff_data.bottleneck) <= 3:
			our_nearby += 1
	
	# Jeśli mamy wystarczająco jednostek
	if our_nearby >= cutoff_data.units_needed:
		# Cavalry i Knight zawsze warto odcinać
		if enemy.type in ["cavalry", "knight"]:
			return true
		
		# Inne jednostki - tylko jeśli łatwo (≤2 jednostki)
		if cutoff_data.units_needed <= 2:
			return true
	
	return false

# ============================================================================
# UPDATE MEMORY
# ============================================================================

func update_memory(state: Dictionary):
	var current_hex_count = state.my_connected_hexes.size()
	
	if current_hex_count < memory.previous_hex_count:
		if DEBUG: print("AI %d: Straciłem terytorium!" % team)
	
	memory.previous_hex_count = current_hex_count
	
	if state.castle_threats.is_empty():
		memory.castle_under_attack = false
		memory.castle_attacker_pos = Vector2i.ZERO
	
	memory.detached_territories = state.my_detached_groups

# ============================================================================
# MERGE UNITS
# ============================================================================

func merge_units(state: Dictionary):
	"""Łączy jednostki. Merguje ile może w tej turze (nie tylko 1!)."""
	
	# PRIORYTET 0: Wróg jest PRZY NASZYM ZAMKU - natychmiast merguj żeby móc atakować
	for castle_pos in state.my_castles:
		var enemy_adjacent = false
		for neighbor in hex_grid.get_neighbors(castle_pos):
			if hex_grid.knight_map.has(neighbor) and hex_grid.knight_map[neighbor].team != team:
				enemy_adjacent = true; break
			if hex_grid.spearman_map.has(neighbor) and hex_grid.spearman_map[neighbor].team != team:
				enemy_adjacent = true; break
			if hex_grid.cavalry_map.has(neighbor) and hex_grid.cavalry_map[neighbor].team != team:
				enemy_adjacent = true; break
			if hex_grid.farmer_map.has(neighbor) and hex_grid.farmer_map[neighbor].team != team and hex_grid.farmer_map[neighbor].team != -1:
				enemy_adjacent = true; break
		
		if enemy_adjacent:
			if DEBUG: print("AI %d: WRÓG PRZY ZAMKU %s - priorytetowy merge!" % [team, castle_pos])
			var farmers_near = []
			for unit_data in state.my_units:
				if unit_data.type == "farmer":
					var pos = unit_data.unit.hex_position if is_instance_valid(unit_data.unit) else unit_data.pos
					if hex_distance(pos, castle_pos) <= 3:
						farmers_near.append(pos)
			
			for i in range(farmers_near.size()):
				var pos1 = farmers_near[i]
				if not hex_grid.farmer_map.has(pos1): continue
				for j in range(i + 1, farmers_near.size()):
					var pos2 = farmers_near[j]
					if not hex_grid.farmer_map.has(pos2): continue
					if are_hexes_adjacent(pos1, pos2):
						if DEBUG: print("AI %d: Merguje farmerów %s+%s -> spearman (obrona zamku!)" % [team, pos1, pos2])
						hex_grid.merge_farmers_to_spearman(pos1, pos2)
						await hex_grid.get_tree().create_timer(0.2).timeout
						# Nie return - merguj więcej!
			
			# Merguj knightów
			var knights_near = []
			for unit_data in state.my_units:
				if unit_data.type == "knight":
					var pos = unit_data.unit.hex_position if is_instance_valid(unit_data.unit) else unit_data.pos
					if hex_distance(pos, castle_pos) <= 3:
						knights_near.append(pos)
			
			for i in range(knights_near.size()):
				var pos1 = knights_near[i]
				if not hex_grid.knight_map.has(pos1): continue
				for j in range(i + 1, knights_near.size()):
					var pos2 = knights_near[j]
					if not hex_grid.knight_map.has(pos2): continue
					if are_hexes_adjacent(pos1, pos2):
						if DEBUG: print("AI %d: Merguje knightów %s+%s -> cavalry (obrona zamku!)" % [team, pos1, pos2])
						hex_grid.merge_knights_to_cavalry(pos1, pos2)
						await hex_grid.get_tree().create_timer(0.2).timeout
	
	# PRIORYTET 1: Knights -> Cavalry (wysoky priorytet - cavalry bardzo silne!)
	# Merguj WSZYSTKIE pary knightów które sąsiadują
	var merged_any_knight = true
	while merged_any_knight:
		merged_any_knight = false
		var knights_positions = hex_grid.knight_map.keys().filter(func(pos):
			return hex_grid.knight_map.has(pos) and hex_grid.knight_map[pos].team == team
		)
		
		for i in range(knights_positions.size()):
			var pos1 = knights_positions[i]
			if not hex_grid.knight_map.has(pos1): continue
			if hex_grid.knight_map[pos1].team != team: continue
			
			for j in range(i + 1, knights_positions.size()):
				var pos2 = knights_positions[j]
				if not hex_grid.knight_map.has(pos2): continue
				if hex_grid.knight_map[pos2].team != team: continue
				
				if are_hexes_adjacent(pos1, pos2):
					if DEBUG: print("AI %d: Merguje knightów %s + %s -> cavalry" % [team, pos1, pos2])
					hex_grid.merge_knights_to_cavalry(pos1, pos2)
					await hex_grid.get_tree().create_timer(0.2).timeout
					merged_any_knight = true
					break
			if merged_any_knight:
				break
	
	# PRIORYTET 2: Połącz farmerów BLISKO WROGIEGO ZAMKU
	# Sprawdź WSZYSTKIE wrogie zamki (nie tylko undefended) - chcemy mergować gdy jesteśmy blisko
	var all_enemy_castles = state.enemy_castles + state.undefended_enemy_castles
	all_enemy_castles = all_enemy_castles.filter(func(p): return true)  # deduplicate via set
	var seen_castles = {}
	for castle_pos in all_enemy_castles:
		if seen_castles.has(castle_pos): continue
		seen_castles[castle_pos] = true
		var distance = get_min_unit_distance_to(castle_pos, state.my_units)
		if distance <= 3:  # Zwiększone z 2 do 3 - reaguj wcześniej
			var farmers_near_castle = []
			for unit_data in state.my_units:
				if unit_data.type == "farmer":
					var pos = unit_data.unit.hex_position if is_instance_valid(unit_data.unit) else unit_data.pos
					if hex_distance(pos, castle_pos) <= 3:
						farmers_near_castle.append(pos)
			
			for i in range(farmers_near_castle.size()):
				var pos1 = farmers_near_castle[i]
				if not hex_grid.farmer_map.has(pos1): continue
				for j in range(i + 1, farmers_near_castle.size()):
					var pos2 = farmers_near_castle[j]
					if not hex_grid.farmer_map.has(pos2): continue
					if are_hexes_adjacent(pos1, pos2):
						if DEBUG: print("AI %d: Łączę farmerów %s + %s -> spearman (ATAK NA ZAMEK!)" % [team, pos1, pos2])
						hex_grid.merge_farmers_to_spearman(pos1, pos2)
						await hex_grid.get_tree().create_timer(0.2).timeout
	
	# PRIORYTET 3: Standardowe łączenie Farmers -> Spearman
	# Łącz WSZYSTKIE przylegające pary farmerów (nie tylko jedną na turę!)
	var merged_any_farmer = true
	var farmer_merge_count = 0
	while merged_any_farmer:
		merged_any_farmer = false
		var farmers_positions = hex_grid.farmer_map.keys().filter(func(pos):
			return hex_grid.farmer_map.has(pos) and hex_grid.farmer_map[pos].team == team
		)
		
		for i in range(farmers_positions.size()):
			var pos1 = farmers_positions[i]
			if not hex_grid.farmer_map.has(pos1): continue
			if hex_grid.farmer_map[pos1].team != team: continue
			
			for j in range(i + 1, farmers_positions.size()):
				var pos2 = farmers_positions[j]
				if not hex_grid.farmer_map.has(pos2): continue
				if hex_grid.farmer_map[pos2].team != team: continue
				
				if are_hexes_adjacent(pos1, pos2):
					if DEBUG: print("AI %d: Łączę farmerów %s + %s -> spearman" % [team, pos1, pos2])
					hex_grid.merge_farmers_to_spearman(pos1, pos2)
					await hex_grid.get_tree().create_timer(0.2).timeout
					merged_any_farmer = true
					farmer_merge_count += 1
					break
			if merged_any_farmer:
				break
	
	if farmer_merge_count > 0:
		if DEBUG: print("AI %d: Łącznie zmergowano %d par farmerów" % [team, farmer_merge_count])

# ============================================================================
# BUY UNITS
# ============================================================================

func buy_units(state: Dictionary, kingdom_id: int = -1):
	# Użyj złota konkretnego królestwa (nie sumy team_gold)
	var gold = hex_grid.kingdom_gold.get(kingdom_id, state.gold) if kingdom_id > 0 else state.gold
	var upkeep = hex_grid.calculate_upkeep_for_kingdom(kingdom_id) if kingdom_id > 0 else state.upkeep
	var income = hex_grid.calculate_income_for_kingdom(kingdom_id) if kingdom_id > 0 else state.income
	
	# Rezerwa: gdy mało pól/dochodu - nie trzymaj złota, kup farmera jak tylko masz środki
	var reserve: int
	var net_income = income - upkeep
	var my_unit_count = state.my_units.size()
	
	# KLUCZOWE: Jeśli brak jednostek - kup farmera NATYCHMIAST, rezerwa = 0
	if my_unit_count == 0:
		reserve = 0
		if DEBUG: print("AI %d: BRAK JEDNOSTEK - kupuję natychmiast bez rezerwy!" % team)
	elif net_income <= 0:
		# Biedne królestwo (netto <= 0): złoto i tak nie rośnie - kup bez rezerwy
		reserve = 0
		if DEBUG: print("AI %d: Netto dochód <= 0 - rezerwa = 0, kup farmera!" % team)
	else:
		reserve = 3
	
	var available_gold = max(0, gold - reserve)
	
	if DEBUG: print("AI %d: Złoto: %d, Rezerwacja: %d, Dostępne: %d, Jednostki: %d" % [team, gold, reserve, available_gold, my_unit_count])
	
	if available_gold < hex_grid.FARMER_COST:
		if DEBUG: print("AI %d: Za mało złota na jakąkolwiek jednostkę" % team)
		return
	
	# PRIORYTET #1: Dokup jednostki do ODCIĘCIA jeśli potrzeba!
	for opp in state.cutoff_opportunities:
		if opp.get("can_buy_missing", false) and opp.get("missing_units", 0) > 0:
			var missing = opp.missing_units
			var cost_per_unit = hex_grid.FARMER_COST
			
			if DEBUG: print("AI %d: Dokupuję %d jednostek do ODCIĘCIA wroga %s!" % [team, missing, opp.enemy.type])
			
			# Znajdź najlepsze pozycje do spawnu (blisko celu) dla tego królestwa
			var spawn_positions = find_best_spawn_positions(state, kingdom_id, "farmer")
			var target_fields = []
			for step in opp.move_sequence:
				target_fields.append(step.target)
			
			# Sortuj spawny według bliskości do pól odcięcia
			spawn_positions.sort_custom(func(a, b):
				var a_min_dist = 999999
				var b_min_dist = 999999
				for target in target_fields:
					a_min_dist = min(a_min_dist, hex_distance(a, target))
					b_min_dist = min(b_min_dist, hex_distance(b, target))
				return a_min_dist < b_min_dist
			)
			
			# Kup farmerów do odcięcia - ile złoto pozwala
			var bought = 0
			var max_to_buy = max(missing, int(available_gold / cost_per_unit))
			for spawn_pos in spawn_positions:
				if bought >= max_to_buy:
					break
				
				var current_k_gold = hex_grid.kingdom_gold.get(kingdom_id, 0) if kingdom_id > 0 else hex_grid.team_gold.get(team, 0)
				if current_k_gold < cost_per_unit:
					break
				
				var hex = hex_grid.get_hex_at(spawn_pos)
				if not hex or hex.occupied_object != null:
					continue
				
				hex_grid.place_farmer_at(spawn_pos, team)
				hex_grid.deduct_selected_kingdom_gold(team, cost_per_unit)
				hex_grid.capture_territory(spawn_pos, team)
				if DEBUG: print("AI %d: ✓ FARMER na %s DO ODCIĘCIA!" % [team, spawn_pos])
				bought += 1
				await hex_grid.get_tree().create_timer(0.1).timeout
			
			if bought > 0:
				# Zaktualizuj available_gold
				var updated_k_gold = hex_grid.kingdom_gold.get(kingdom_id, 0) if kingdom_id > 0 else hex_grid.team_gold.get(team, 0)
				available_gold = max(0, updated_k_gold - reserve)
	
	# PRIORYTET #2: Normalne kupowanie
	var current_k_gold = hex_grid.kingdom_gold.get(kingdom_id, 0) if kingdom_id > 0 else hex_grid.team_gold.get(team, 0)
	var units_to_buy = plan_unit_purchases(state, current_k_gold - reserve, kingdom_id)
	
	if DEBUG: print("AI %d: Zaplanowano zakup %d jednostek" % [team, units_to_buy.size()])
	
	for purchase in units_to_buy:
		var unit_type = purchase.type
		var cost = purchase.cost
		
		# Znajdź pozycję do spawnu dla tego typu jednostki
		var spawn_positions = find_best_spawn_positions(state, kingdom_id, unit_type)
		if spawn_positions.is_empty():
			continue
		
		var position = spawn_positions[0]
		
		# Sprawdź złoto konkretnego królestwa
		var check_gold = hex_grid.kingdom_gold.get(kingdom_id, 0) if kingdom_id > 0 else hex_grid.team_gold.get(team, 0)
		if check_gold < cost:
			continue
		
		var hex = hex_grid.get_hex_at(position)
		if not hex or hex.occupied_object != null:
			continue
		
		if unit_type == "farmer":
			hex_grid.place_farmer_at(position, team)
			hex_grid.deduct_selected_kingdom_gold(team, cost)
			hex_grid.capture_territory(position, team)
			if DEBUG: print("AI %d: ✓ Kupiono FARMER na %s za %d" % [team, position, cost])
		elif unit_type == "knight":
			hex_grid.place_knight_at(position, team)
			hex_grid.deduct_selected_kingdom_gold(team, cost)
			hex_grid.capture_territory(position, team)
			if DEBUG: print("AI %d: ✓ Kupiono KNIGHT na %s za %d" % [team, position, cost])
		elif unit_type == "spearman":
			hex_grid.place_spearman_at(position, team)
			hex_grid.deduct_selected_kingdom_gold(team, cost)
			hex_grid.capture_territory(position, team)
			if DEBUG: print("AI %d: ✓ Kupiono SPEARMAN na %s za %d" % [team, position, cost])
		elif unit_type == "cavalry":
			hex_grid.place_cavalry_at(position, team)
			hex_grid.deduct_selected_kingdom_gold(team, cost)
			hex_grid.capture_territory(position, team)
			if DEBUG: print("AI %d: ✓ Kupiono CAVALRY na %s za %d" % [team, position, cost])
		
		await hex_grid.get_tree().create_timer(0.1).timeout

func plan_unit_purchases(state: Dictionary, budget: int, kingdom_id: int = -1) -> Array:
	"""Planuje zakup jednostek.
	
	Filozofia:
	- Wczesna gra (mało pól, mało dochodu): farmerzy = ekspansja = dochód
	- Średnia gra: mieszaj farmerów z knightami gdy masz nadwyżkę
	- Duże złoto (>40) lub duży dochód (>15): czas na knightów / cavalry
	- Nigdy nie trzymaj złota bezczynnie!
	"""
	var purchases = []
	var remaining_budget = budget
	var my_hex_count = state.my_connected_hexes.size()
	var my_farmer_count = 0
	var my_knight_count = 0
	var my_cavalry_count = 0
	var my_spearman_count = 0
	
	for u in state.my_units:
		match u.type:
			"farmer":   my_farmer_count += 1
			"knight":   my_knight_count += 1
			"cavalry":  my_cavalry_count += 1
			"spearman": my_spearman_count += 1
	
	var my_combat_count = my_knight_count + my_cavalry_count + my_spearman_count
	
	# Policz siłę wroga
	var threat_level = 0
	var enemy_knight_near = false
	var enemy_cavalry_near = false
	var enemy_total_strength = 0
	
	if not state.my_castles.is_empty():
		var castle_pos = state.my_castles[0]
		for enemy in state.enemy_units:
			enemy_total_strength += enemy.strength
			var dist = hex_distance(enemy.pos, castle_pos)
			if dist <= 8:
				match enemy.type:
					"knight":
						threat_level += 3
						if dist <= 5: enemy_knight_near = true
					"cavalry":
						threat_level += 5
						if dist <= 6: enemy_cavalry_near = true
					"spearman": threat_level += 2
					_: threat_level += 1
	
	# Policz mój dochód i czy mam nadwyżkę - użyj danych konkretnego królestwa!
	var k_income = hex_grid.calculate_income_for_kingdom(kingdom_id) if kingdom_id > 0 else state.income
	var k_upkeep = hex_grid.calculate_upkeep_for_kingdom(kingdom_id) if kingdom_id > 0 else state.upkeep
	var net_income = k_income - k_upkeep
	# is_rich: efektywny budżet (już po odjęciu rezerwy) >= 30
	var is_rich = remaining_budget >= 30
	# Dobry dochód = 18+ netto → AI stać na drogie jednostki
	var has_good_income = net_income >= 18
	
	# Pomocnicza funkcja: czy mogę kupić jednostkę o danym koszcie zakupu i utrzymania?
	var current_gold = hex_grid.kingdom_gold.get(kingdom_id, state.gold) if kingdom_id > 0 else state.gold
	var can_afford_unit = func(buy_cost: int, upkeep_cost: int) -> bool:
		var gold_after = current_gold - buy_cost
		var net_after = net_income - upkeep_cost
		if net_after >= 0:
			return true
		return gold_after >= abs(net_after) * 3
	
	print("AI %d: plan_purchases: budżet=%d, pola=%d, farmerzy=%d, bojowe=%d, zagrożenie=%d, bogaty=%s, dochód=%d" % 
		[team, remaining_budget, my_hex_count, my_farmer_count, my_combat_count, threat_level, is_rich, net_income])
	
	# ============================================================
	# FAZA 1: SYTUACJE KRYZYSOWE - OBRONA PRZEZ ODCIĘCIE, NIE COFANIE
	# ============================================================
	
	var enemy_spearman_near = false
	var enemy_spearman_count_near = 0
	var castle_under_cutoff_threat = false
	
	if not state.my_castles.is_empty():
		var castle_pos = state.my_castles[0]
		for enemy in state.enemy_units:
			var dist = hex_distance(enemy.pos, castle_pos)
			if dist <= 6:
				match enemy.type:
					"spearman":
						enemy_spearman_near = true
						enemy_spearman_count_near += 1
					"knight":
						enemy_knight_near = true
						if dist <= 5: castle_under_cutoff_threat = true
					"cavalry":
						enemy_cavalry_near = true
						castle_under_cutoff_threat = true
	
	var has_cutoff_opportunities = not state.cutoff_opportunities.is_empty()
	
	# Zamek zagrożony przez knight/cavalry ale BRAK możliwości odcięcia → kup knight/cavalry jako kontrę
	if castle_under_cutoff_threat and not has_cutoff_opportunities:
		if enemy_cavalry_near and remaining_budget >= hex_grid.CAVALRY_COST and can_afford_unit.call(hex_grid.CAVALRY_COST, hex_grid.CAVALRY_UPKEEP):
			purchases.append({"type": "cavalry", "cost": hex_grid.CAVALRY_COST})
			remaining_budget -= hex_grid.CAVALRY_COST
			current_gold -= hex_grid.CAVALRY_COST
			net_income -= hex_grid.CAVALRY_UPKEEP
			my_combat_count += 1
			if DEBUG: print("AI %d: Cavalry wroga, brak odcięcia - kupuję cavalry!" % team)
		elif remaining_budget >= hex_grid.KNIGHT_COST and can_afford_unit.call(hex_grid.KNIGHT_COST, hex_grid.KNIGHT_UPKEEP):
			purchases.append({"type": "knight", "cost": hex_grid.KNIGHT_COST})
			remaining_budget -= hex_grid.KNIGHT_COST
			current_gold -= hex_grid.KNIGHT_COST
			net_income -= hex_grid.KNIGHT_UPKEEP
			my_combat_count += 1
			if DEBUG: print("AI %d: Knight wroga, brak odcięcia - kupuję knight!" % team)
	
	# Spearman blisko → kup spearmana jako kontrę
	elif enemy_spearman_near and my_combat_count == 0 and remaining_budget >= hex_grid.SPEARMAN_COST:
		purchases.append({"type": "spearman", "cost": hex_grid.SPEARMAN_COST})
		remaining_budget -= hex_grid.SPEARMAN_COST
		my_combat_count += 1
		if DEBUG: print("AI %d: Spearman wroga blisko - kupuję spearmana!" % team)
	
	# ============================================================
	# FAZA 2: STRATEGIA GŁÓWNA - na podstawie bogactwa i sytuacji
	# ============================================================
	
	# BOGATA GRA (>=30 efektywnego złota) lub DOBRY DOCHÓD (>=18 netto)
	if is_rich or has_good_income:
		# Cavalry: kup jeśli mamy >=60 lub wróg ma cavalry
		if remaining_budget >= hex_grid.CAVALRY_COST and (remaining_budget >= 60 or enemy_cavalry_near) and can_afford_unit.call(hex_grid.CAVALRY_COST, hex_grid.CAVALRY_UPKEEP):
			purchases.append({"type": "cavalry", "cost": hex_grid.CAVALRY_COST})
			remaining_budget -= hex_grid.CAVALRY_COST
			current_gold -= hex_grid.CAVALRY_COST
			net_income -= hex_grid.CAVALRY_UPKEEP
			if DEBUG: print("AI %d: Bogata gra - kupuję cavalry!" % team)
		
		# Knighci: zawsze gdy mamy kasę i brak wystarczającej siły bojowej
		var want_knights = (my_combat_count < 2) or (my_farmer_count >= 3 and my_combat_count < my_farmer_count / 2) or is_rich
		if want_knights:
			var knights_to_buy = 0
			if remaining_budget >= hex_grid.KNIGHT_COST * 2:
				knights_to_buy = 2
			elif remaining_budget >= hex_grid.KNIGHT_COST:
				knights_to_buy = 1
			
			var bought_knights = 0
			while bought_knights < knights_to_buy and remaining_budget >= hex_grid.KNIGHT_COST and can_afford_unit.call(hex_grid.KNIGHT_COST, hex_grid.KNIGHT_UPKEEP):
				purchases.append({"type": "knight", "cost": hex_grid.KNIGHT_COST})
				remaining_budget -= hex_grid.KNIGHT_COST
				current_gold -= hex_grid.KNIGHT_COST
				net_income -= hex_grid.KNIGHT_UPKEEP
				my_combat_count += 1
				bought_knights += 1
			if bought_knights > 0:
				if DEBUG: print("AI %d: Bogata gra - kupuję %d knight(ów)" % [team, bought_knights])
	
	# STRATEGIA AGRESYWNA: zawsze knighty
	elif current_strategy == Strategy.AGGRESSIVE and my_combat_count < 2:
		while remaining_budget >= hex_grid.KNIGHT_COST and can_afford_unit.call(hex_grid.KNIGHT_COST, hex_grid.KNIGHT_UPKEEP):
			purchases.append({"type": "knight", "cost": hex_grid.KNIGHT_COST})
			remaining_budget -= hex_grid.KNIGHT_COST
			current_gold -= hex_grid.KNIGHT_COST
			net_income -= hex_grid.KNIGHT_UPKEEP
			my_combat_count += 1
	
	# ============================================================
	# FAZA 3: RESZTA BUDŻETU - farmerzy / spearmani
	# Nigdy nie zostaw złota! Zawsze coś kup.
	# ============================================================
	
	# Sprawdź czy królestwo jest zamknięte w murach (nie może się rozwijać)
	var is_walled_in = false
	var check_castle = Vector2i.ZERO
	if kingdom_id > 0:
		for coords in hex_grid.castle_map:
			if hex_grid.castle_map[coords].team == team and \
			   hex_grid.castle_kingdom_id.get(coords, 0) == kingdom_id:
				check_castle = coords
				break
	if check_castle == Vector2i.ZERO and not state.my_castles.is_empty():
		check_castle = state.my_castles[0]
	
	if check_castle != Vector2i.ZERO:
		var castle_territory: Array = []
		if kingdom_id > 0:
			castle_territory = hex_grid.get_kingdom_connected_territories(kingdom_id)
		else:
			castle_territory = state.my_connected_hexes
		
		if castle_territory.size() <= 4:
			var territory_set: Dictionary = {}
			for t in castle_territory:
				territory_set[t] = true
			var can_expand = false
			for t_hex in castle_territory:
				if can_expand:
					break
				for nb in hex_grid.get_neighbors(t_hex):
					if not territory_set.has(nb) and hex_grid.hex_map.has(nb):
						if not hex_grid.has_wall_between(t_hex, nb):
							can_expand = true
							break
			if not can_expand:
				is_walled_in = true
				if DEBUG: print("AI %d: Królestwo zamknięte w murach! Oszczędzam na spearmana." % team)
	
	# Zamknięci w murach + już mamy farmera = skip farmerów, oszczędzaj na spearmana
	var skip_farmers = is_walled_in and my_farmer_count > 0
	
	if is_walled_in and my_farmer_count == 0 and my_spearman_count == 0:
		# Brak farmerów I brak spearmana - kup spearmana żeby przebić mury
		if remaining_budget >= hex_grid.SPEARMAN_COST:
			purchases.append({"type": "spearman", "cost": hex_grid.SPEARMAN_COST})
			remaining_budget -= hex_grid.SPEARMAN_COST
			my_spearman_count += 1
			my_combat_count += 1
			skip_farmers = true
			if DEBUG: print("AI %d: Zamknięty w murach, brak farmerów - kupuję spearmana!" % team)
	
	if not skip_farmers:
		while remaining_budget >= hex_grid.FARMER_COST and purchases.size() < 6:
			purchases.append({"type": "farmer", "cost": hex_grid.FARMER_COST})
			remaining_budget -= hex_grid.FARMER_COST
			my_farmer_count += 1
	
	if DEBUG: print("AI %d: Zaplanowano %d zakupów, zostaje %d złota" % [team, purchases.size(), remaining_budget])
	return purchases

func find_best_spawn_positions(state: Dictionary, kingdom_id: int = -1, unit_type: String = "") -> Array:
	"""Znajduje najlepsze pozycje do spawnu jednostek - dla konkretnego królestwa i typu jednostki."""
	var positions = []
	
	if state.my_castles.is_empty():
		return positions
	
	# Znajdź zamek konkretnego królestwa
	var castle_pos = Vector2i.ZERO
	if kingdom_id > 0:
		for coords in hex_grid.castle_map:
			if hex_grid.castle_map[coords].team == team and \
			   hex_grid.castle_kingdom_id.get(coords, 0) == kingdom_id:
				castle_pos = coords
				break
	if castle_pos == Vector2i.ZERO:
		castle_pos = state.my_castles[0]
	
	# Terytorium TYLKO tego królestwa
	var connected_territory: Array
	if kingdom_id > 0:
		connected_territory = hex_grid.get_kingdom_connected_territories(kingdom_id)
	else:
		connected_territory = state.my_connected_hexes
	
	# Zbierz kandydatów
	var candidates: Dictionary = {}
	
	for nb in hex_grid.get_neighbors(castle_pos):
		if hex_grid.hex_map.has(nb):
			candidates[nb] = true
	
	for hex_pos in connected_territory:
		for nb in hex_grid.get_neighbors(hex_pos):
			if hex_grid.hex_map.has(nb):
				candidates[nb] = true
		candidates[hex_pos] = true
	
	var scored_positions = []
	
	for neighbor in candidates.keys():
		if not hex_grid.hex_map.has(neighbor):
			continue
		
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex or hex.occupied_object != null:
			continue
		
		var owner = hex_grid.territory_map.get(neighbor, 0)
		
		# Pole jest ważne jeśli:
		var is_valid_spawn = false
		if neighbor in connected_territory:
			is_valid_spawn = true
		elif castle_pos in hex_grid.get_neighbors(neighbor):
			is_valid_spawn = true
		else:
			for nn in hex_grid.get_neighbors(neighbor):
				if nn in connected_territory:
					is_valid_spawn = true
					break
		
		if not is_valid_spawn:
			continue
		
		var wall_count = hex_grid.count_walls_around(neighbor)
		var target_unit = hex.occupied_object

		# === FILTRY WEDŁUG TYPU JEDNOSTKI ===
		if unit_type == "farmer":
			# Farmer NIE na pole z JAKIMIKOLWIEK murami
			if wall_count > 0:
				continue
			# Farmer może kupić TYLKO na pustym polu lub na wrogim farmerze
			if target_unit != null:
				if not (target_unit is Farmer and target_unit.team != team):
					continue
		elif unit_type == "spearman":
			# Spearman NIE na pole z murami
			if wall_count > 0:
				continue
			# Spearman może kupić na farmerze lub spearmanie
			if target_unit != null:
				if not (target_unit is Farmer or target_unit is Spearman) or target_unit.team == team:
					continue
		elif unit_type == "knight":
			# Knight może na puste mury
			# Knight może kupić na farmerze, spearmanie (nawet w murach)
			# Knight może kupić na knightzie TYLKO bez murów
			if target_unit is Knight and target_unit.team != team:
				if wall_count > 0:
					continue
		elif unit_type == "cavalry":
			# Cavalry może na puste mury
			# Cavalry może kupić na knightzie TYLKO bez murów
			# Cavalry może kupić na cavalry TYLKO bez murów
			if target_unit is Knight and target_unit.team != team:
				if wall_count > 0:
					continue
			if target_unit is Cavalry and target_unit.team != team:
				if wall_count > 0:
					continue
		
		var score = 0
		
		# Punktacja bazowa
		if owner > 0 and owner != team:
			score = 500
		elif owner == 0:
			score = 400
		elif owner == team:
			score = 10
		else:
			continue
		
		# Kara bezpieczeństwa
		if owner != team:
			var safety_penalty = calculate_spawn_safety(neighbor, state)
			score -= safety_penalty
		
		# Bonus za wąskie gardło
		var own_neighbor_count = 0
		for nb2 in hex_grid.get_neighbors(neighbor):
			var nb2_owner = hex_grid.territory_map.get(nb2, 0)
			if nb2_owner == team:
				own_neighbor_count += 1
		
		if own_neighbor_count >= 2 and owner == 0:
			score += 60
		elif own_neighbor_count >= 1 and owner == 0:
			score += 30
		
		# Bonus za bliskość frontu
		if not state.enemy_units.is_empty():
			var min_dist_to_enemy = 999999
			for enemy in state.enemy_units:
				var dist = hex_distance(neighbor, enemy.pos)
				min_dist_to_enemy = min(min_dist_to_enemy, dist)
			
			if min_dist_to_enemy <= 3:
				score += 50
			elif min_dist_to_enemy <= 5:
				score += 20
		
		scored_positions.append({
			"pos": neighbor,
			"score": score
		})
	
	# Sortuj według wyniku
	scored_positions.sort_custom(func(a, b): return a.score > b.score)
	
	for item in scored_positions:
		positions.append(item.pos)
	
	return positions

func calculate_spawn_safety(pos: Vector2i, state: Dictionary) -> int:
	"""Oblicza karę bezpieczeństwa - czy wróg może nas szybko odciąć?"""
	var penalty = 0
	
	# Sprawdź czy jesteśmy wąskim gardłem (łatwo odciąć)
	var friendly_neighbors = count_friendly_neighbors(pos, team)
	
	if friendly_neighbors <= 1:
		penalty += 40  # BARDZO niebezpieczne - łatwo odciąć
	elif friendly_neighbors == 2:
		penalty += 20  # Niebezpieczne
	
	# Sprawdź czy są wrogowie blisko
	var enemies_very_close = 0
	for enemy in state.enemy_units:
		var dist = hex_distance(pos, enemy.pos)
		if dist <= 2:
			enemies_very_close += 1
	
	penalty += enemies_very_close * 15
	
	return penalty

# ============================================================================
# BUILD WALLS
# ============================================================================

func build_walls(state: Dictionary):
	"""Buduje mury wokół ważnych hexów"""
	var hexes_to_wall = plan_hexes_for_walling(state)
	
	if hexes_to_wall.is_empty():
		return
		
	var net_income = state.income - state.upkeep
	if net_income <= 0:
		return
	
	var walls_built = 0
	var max_hexes = 3
	
	for hex_pos in hexes_to_wall:
		if walls_built >= max_hexes:
			break
		
		var cost = hex_grid.WALL_COST_PER_HEX
		if hex_grid.get_selected_kingdom_gold(team) < cost:
			break
		
		var walls_created = hex_grid.create_hex_walls(hex_pos, team)
		
		if walls_created > 0:
			hex_grid.deduct_selected_kingdom_gold(team, cost)
			walls_built += 1
			if DEBUG: print("AI %d: Zbudowano %d murów wokół %s za %d złota" % [team, walls_created, hex_pos, cost])
		
		await hex_grid.get_tree().create_timer(0.1).timeout

func plan_hexes_for_walling(state: Dictionary) -> Array:
	var hexes = []
	
	# Sprawdź czy gracz (team 1) może w ogóle dotrzeć do naszego zamku
	var player_can_reach = is_player_reachable(state)
	
	# Jeśli gracz nie może dotrzeć - nie muruj w ogóle
	if not player_can_reach:
		return hexes
	
	# TYLKO gdy zamek jest pod atakiem
	if memory.castle_under_attack:
		for castle_pos in state.my_castles:
			if not has_all_walls_on_hex(castle_pos):
				if castle_pos not in hexes:
					hexes.append(castle_pos)
	
	# Gdy cavalry/knight wroga jest blisko zamku (dist ≤ 4)
	if not state.my_castles.is_empty():
		var castle_pos = state.my_castles[0]
		var strong_threat_close = false
		for enemy in state.enemy_units:
			if enemy.type in ["cavalry", "knight"]:
				if hex_distance(enemy.pos, castle_pos) <= 4:
					strong_threat_close = true
					break
		if strong_threat_close:
			if not has_all_walls_on_hex(castle_pos):
				if castle_pos not in hexes:
					hexes.append(castle_pos)
	
	return hexes

func is_player_reachable(state: Dictionary) -> bool:
	"""Sprawdza czy gracz (team 1) może dotrzeć do naszego terytorium przez flood fill"""
	if state.my_castles.is_empty():
		return true  # Nie wiemy - zakładamy zagrożenie
	
	# Zbierz wszystkie hexy gracza
	var player_hexes = {}
	for coords in hex_grid.territory_map:
		if hex_grid.territory_map[coords] == 1:
			player_hexes[coords] = true
	
	if player_hexes.is_empty():
		return false
	
	# Flood fill od terytorium gracza przez neutralne i własne hexy
	# Sprawdź czy możemy dotrzeć do któregoś z naszych hexów
	var visited = {}
	var queue = player_hexes.keys()
	for pos in queue:
		visited[pos] = true
	
	var our_territory = {}
	for coords in hex_grid.territory_map:
		if hex_grid.territory_map[coords] == team:
			our_territory[coords] = true
	
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		
		if our_territory.has(current):
			return true  # Gracz może dotrzeć do nas
		
		for neighbor in hex_grid.get_neighbors(current):
			if visited.has(neighbor):
				continue
			if not hex_grid.hex_map.has(neighbor):
				continue
			var owner = hex_grid.territory_map.get(neighbor, 0)
			# Można przejść przez neutralne, własne gracza lub nasze
			if owner == 0 or owner == 1 or owner == team:
				visited[neighbor] = true
				queue.append(neighbor)
	
	return false  # Gracz nie może dotrzeć

# ============================================================================
# MOVE UNITS
# ============================================================================

# ============================================================================
# MOVEMENT HELPERS
# ============================================================================

func check_and_freeze_isolated_units(state: Dictionary):
	"""Sprawdza izolację jednostek i zamraża te które właśnie zostały odcięte"""
	var connected_territory = hex_grid.get_connected_territories(team)
	var connected_set = {}
	for pos in connected_territory:
		connected_set[pos] = true
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		
		var unit_pos = unit_data.unit.hex_position
		var is_isolated = not connected_set.has(unit_pos)
		
		if is_isolated:
			# Jednostka jest izolowana
			if not isolated_units_freeze.has(unit_data.unit):
				# Właśnie została odcięta - zapamiętaj turę
				isolated_units_freeze[unit_data.unit] = hex_grid.current_round
				if DEBUG: print("AI %d: %s @ %s została ODCIĘTA - zamrożona na 1 turę" % [team, unit_data.type, unit_pos])
		else:
			# Jednostka połączona - usuń z listy zamrożonych
			if isolated_units_freeze.has(unit_data.unit):
				if DEBUG: print("AI %d: %s @ %s PRZYWRÓCONA do królestwa" % [team, unit_data.type, unit_pos])
				isolated_units_freeze.erase(unit_data.unit)

func move_all_units(state: Dictionary):
	"""Rusza wszystkie jednostki według strategii"""
	if DEBUG: print("AI %d: === Rozpoczynam ruch %d jednostek (Strategia: %s) ===" % [team, state.my_units.size(), Strategy.keys()[current_strategy]])
	
	# NOWE: Sprawdź i zamroź odcięte jednostki
	check_and_freeze_isolated_units(state)
	force_stagnant_units_to_attack(state)
	
	var sorted_goals = strategic_goals.duplicate()
	sorted_goals.sort_custom(func(a, b): return a.priority > b.priority)
	
	for goal in sorted_goals:
		if _is_interrupted(): return
		# Sprawdź czy są wolne jednostki
		var free_units_exist = false
		for u in state.my_units:
			if is_instance_valid(u.unit) and u.unit not in hex_grid.units_moved_this_turn:
				free_units_exist = true
				break
		if not free_units_exist:
			break
		
		match goal.type:
			"eliminate_high_value_target":
				await eliminate_high_value_target(state, goal)
			"fortify_bottleneck":
				await fortify_bottleneck(state, goal)
			"defend_from_cutoff":
				await defend_from_cutoff(state, goal)
			"connect_territory":
				await connect_detached_territory(state, goal)
			"capture_castle":
				await capture_castle(state, goal)
			"capture_walled_castle":
				await capture_castle(state, goal)
			"capture_bandit_camp":
				await capture_bandit_camp(state, goal)
			"surround_enemy":
				await surround_enemy(state, goal)
			"defend_castle":
				await defend_castle_single_threat(state, goal)
			"expand_around_castle":
				await expand_around_castle(state)
			"expand_territory":
				await expand_aggressively(state)
	
	if DEBUG: print("AI %d: === Zakończono ruch jednostek ===" % team)

# ============================================================================
# MOVEMENT STRATEGIES
# ============================================================================

func defend_from_cutoff(state: Dictionary, goal: Dictionary):
	"""Broni jednostkę przed odcięciem - buduje mury LUB wysyła 1 jednostkę. Nie blokuje reszty armii."""
	var threat_data = goal.threat_data
	var unit_pos = threat_data.unit_pos
	
	if DEBUG: print("AI %d: OBRONA PRZED ODCIĘCIEM jednostki %s @ %s" % [team, threat_data.unit.type, unit_pos])
	
	# Strategia 1: Zbuduj mury na wąskim gardle
	if threat_data.connections <= 2:
		var gold = hex_grid.get_selected_kingdom_gold(team)
		if gold >= hex_grid.WALL_COST_PER_HEX:
			var best_wall_hex = null
			var max_threat_dist = -1
			
			for vuln in threat_data.vulnerable_points:
				var conn_point = vuln.connection_point
				var walls_around = count_walls_around(conn_point)
				if walls_around < 6:
					if vuln.distance > max_threat_dist:
						max_threat_dist = vuln.distance
						best_wall_hex = conn_point
			
			if best_wall_hex != null:
				if DEBUG: print("AI %d: Buduję PEŁNY HEX murów @ %s" % [team, best_wall_hex])
				var walls_created = hex_grid.create_hex_walls(best_wall_hex, team)
				if walls_created > 0:
					hex_grid.deduct_selected_kingdom_gold(team, hex_grid.WALL_COST_PER_HEX)
					if DEBUG: print("AI %d: Zbudowano %d murów dla ochrony" % [team, walls_created])
					return  # Mury postawione - reszta jednostek może ekspandować
	
	# Strategia 2: Wyślij MAKSYMALNIE 1 jednostkę do ataku na zagrożenie
	# (nie monopolizuj całej armii na obronę jednej jednostki)
	var nearest_threat = null
	var min_dist = 999999
	
	for vuln in threat_data.vulnerable_points:
		if vuln.distance < min_dist:
			min_dist = vuln.distance
			nearest_threat = vuln.enemy
	
	if nearest_threat != null:
		var best_defender = null
		var defender_min_dist = 999999
		
		for unit_data in state.my_units:
			if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
				continue
			# Preferuj jednostkę NAJBLIŻEJ zagrożenia, tylko bojowe
			if unit_data.type in ["knight", "cavalry", "spearman"]:
				var current_pos = unit_data.unit.hex_position
				var dist = hex_distance(current_pos, nearest_threat.pos)
				if dist < defender_min_dist:
					defender_min_dist = dist
					best_defender = unit_data
		
		if best_defender != null:
			var current_pos = best_defender.unit.hex_position
			var moves = get_possible_moves(best_defender.type, current_pos)
			var best_move = find_move_towards_target(current_pos, moves, nearest_threat.pos)
			if best_move != Vector2i.ZERO:
				if DEBUG: print("AI %d: %s atakuje zagrażającego wroga -> %s (1 jednostka, reszta ekspanduje)" % [team, best_defender.type, best_move])
				await execute_move(best_defender.unit, best_defender, best_move)
			# KLUCZOWE: return po 1 jednostce - reszta armii dostaje szansę na ekspansję

func connect_detached_territory(state: Dictionary, goal: Dictionary):
	"""Łączy odłączone terytorium z głównym"""
	var group = goal.target_group
	
	if DEBUG: print("AI %d: Łączę odłączone terytorium (%d hexów)" % [team, group.size])
	
	# Znajdź jednostki do wysłania
	var units_to_send = []
	for unit_data in state.my_units:
		if is_instance_valid(unit_data.unit) and unit_data.unit not in hex_grid.units_moved_this_turn:
			# Preferuj silniejsze jednostki jeśli niebezpieczne
			if not group.safe and unit_data.type in ["knight", "cavalry"]:
				units_to_send.append(unit_data)
			elif group.safe:
				units_to_send.append(unit_data)
	
	# Sortuj według odległości do grupy
	units_to_send.sort_custom(func(a, b):
		return hex_distance(a.pos, group.center) < hex_distance(b.pos, group.center)
	)
	
	# Ruszaj w kierunku grupy
	for unit_data in units_to_send:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var current_pos = unit_data.unit.hex_position
		var moves = get_possible_moves(unit_data.type, current_pos)
		if moves.is_empty():
			continue
		
		var best_move = find_move_towards_target(current_pos, moves, group.center)
		
		if best_move != Vector2i.ZERO:
			if DEBUG: print("AI %d: %s -> %s (kierunek: odłączona grupa)" % [team, unit_data.type, best_move])
			await execute_move(unit_data.unit, unit_data, best_move)

func eliminate_high_value_target(state: Dictionary, goal: Dictionary):
	"""Silna jednostka AI (knight/cavalry) atakuje silną jednostkę wroga (knight/cavalry) w zasięgu 1"""
	var attacker_data = goal.attacker
	var target_pos = goal.target_pos
	var target_type = goal.target_type
	
	# Sprawdź że jednostka atakująca nadal istnieje i nie ruszyła się
	if not is_instance_valid(attacker_data.unit) or attacker_data.unit in hex_grid.units_moved_this_turn:
		return
	
	# Sprawdź że cel nadal istnieje
	var target_still_exists = false
	if target_type == "knight" and hex_grid.knight_map.has(target_pos):
		var k = hex_grid.knight_map[target_pos]
		if is_instance_valid(k) and k.team != team:
			target_still_exists = true
	elif target_type == "cavalry" and hex_grid.cavalry_map.has(target_pos):
		var c = hex_grid.cavalry_map[target_pos]
		if is_instance_valid(c) and c.team != team:
			target_still_exists = true
	
	if not target_still_exists:
		if DEBUG: print("AI %d: Cel eliminacji %s @ %s już nie istnieje" % [team, target_type, target_pos])
		return
	
	# Sprawdź że cel jest nadal w zasięgu
	var current_pos = attacker_data.unit.hex_position
	var moves = get_possible_moves(attacker_data.type, current_pos)
	if target_pos not in moves:
		if DEBUG: print("AI %d: Cel %s @ %s poza zasięgiem %s" % [team, target_type, target_pos, attacker_data.type])
		return
	
	if DEBUG: print("AI %d: ⚔️ ELIMINACJA: %s @ %s zabija %s @ %s!" % [team, attacker_data.type, current_pos, target_type, target_pos])
	await execute_move(attacker_data.unit, attacker_data, target_pos)

func capture_castle(state: Dictionary, goal: Dictionary):
	"""Próbuje zdobyć wrogi zamek"""
	var castle_pos = goal.position
	var is_walled = goal.type == "capture_walled_castle"
	
	if not is_castle_reachable(state.my_castles[0] if not state.my_castles.is_empty() else castle_pos, castle_pos):
		if DEBUG: print("AI %d: Zamek %s NIEOSIĄGALNY - pomijam" % [team, castle_pos])
		return
	
	if DEBUG: print("AI %d: Atakuję zamek %s (walled: %s)" % [team, castle_pos, is_walled])
	
	# Znajdź odpowiednie jednostki
	var suitable_units = []
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var can_capture = false
		if is_walled:
			can_capture = unit_data.type in ["knight", "cavalry"]
		else:
			can_capture = unit_data.type in ["spearman", "knight", "cavalry"]
		
		if can_capture:
			suitable_units.append(unit_data)
	
	# Sortuj według odległości (najbliższe pierwsze)
	suitable_units.sort_custom(func(a, b):
		return hex_distance(a.pos, castle_pos) < hex_distance(b.pos, castle_pos)
	)
	
	# Najpierw spróbuj bezpośredniego przejęcia - ZAWSZE wykonaj jeśli w zasięgu!
	for unit_data in suitable_units:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var current_pos = unit_data.unit.hex_position  # ZAWSZE aktualna pozycja
		var moves = get_possible_moves(unit_data.type, current_pos)
		
		if castle_pos in moves:
			if DEBUG: print("AI %d: %s ZAJMUJE ZAMEK %s!" % [team, unit_data.type, castle_pos])
			await execute_move(unit_data.unit, unit_data, castle_pos)
			return  # Zamek przejęty!
	
	# Zbliż się do zamku - NIE sprawdzaj ryzyka gdy celem jest zamek (strata tury!)
	for unit_data in suitable_units:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var current_pos = unit_data.unit.hex_position  # ZAWSZE aktualna pozycja
		var moves = get_possible_moves(unit_data.type, current_pos)
		var best_move = find_move_towards_target(current_pos, moves, castle_pos)
		if best_move != Vector2i.ZERO:
			# Przy ataku na zamek: sprawdź ryzyko TYLKO dla silnych jednostek (knight/cavalry)
			# Spearman zawsze idzie na zamek - opłaca się nawet z ryzykiem
			var skip_risk_check = unit_data.type in ["spearman", "farmer"]
			var risk = evaluate_move_cutoff_risk(unit_data, best_move, state)
			if not skip_risk_check and not risk.worth_it and risk.risk_level >= 0.9:
				# Tylko blokuj jeśli pewne odcięcie silnej jednostki
				if DEBUG: print("AI %d: ⚠️ %s wstrzymuje atak (pewne odcięcie silnej jednostki)" % [team, unit_data.type])
				var safe_move = find_safe_alternative_move(unit_data, best_move, state)
				if safe_move != Vector2i.ZERO:
					await execute_move(unit_data.unit, unit_data, safe_move)
				continue
			if DEBUG: print("AI %d: %s -> %s (cel: zamek)" % [team, unit_data.type, best_move])
			await execute_move(unit_data.unit, unit_data, best_move)

func capture_bandit_camp(state: Dictionary, goal: Dictionary):
	"""Zajmuje obóz bandytów - wysyła WSZYSTKIE pobliskie jednostki bojowe"""
	var camp_pos = goal.position
	var distance = goal.get("distance", 99)
	
	if DEBUG: print("AI %d: ⚔️ ATAK NA OBÓZ BANDYTÓW @ %s (dystans: %d, priorytet: %d)" % [team, camp_pos, distance, goal.priority])
	
	# Zbierz WSZYSTKIE jednostki bojowe które mogą dotrzeć do obozu
	var attacking_units = []
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		if unit_data.type in ["spearman", "knight", "cavalry"]:
			var dist = hex_distance(unit_data.pos, camp_pos)
			# Jeśli obóz BARDZO blisko (1-3 pola), użyj WSZYSTKICH jednostek w promieniu 4
			# Jeśli dalej, użyj tylko najbliższych
			if distance <= 3 and dist <= 4:
				attacking_units.append(unit_data)
			elif dist <= 3:
				attacking_units.append(unit_data)
	
	if attacking_units.is_empty():
		if DEBUG: print("AI %d: Brak dostępnych jednostek do ataku na obóz" % team)
		return
	
	# Sortuj po odległości - najbliższe atakują pierwsze
	attacking_units.sort_custom(func(a, b): 
		return hex_distance(a.pos, camp_pos) < hex_distance(b.pos, camp_pos)
	)
	
	if DEBUG: print("AI %d: Wysyłam %d jednostek do ataku na obóz!" % [team, attacking_units.size()])
	
	# Wysyłaj jednostki jedną po drugiej
	for unit_data in attacking_units:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var current_pos = unit_data.unit.hex_position  # ZAWSZE aktualna pozycja
		var moves = get_possible_moves(unit_data.type, current_pos)
		
		if camp_pos in moves:
			# Bezpośrednie przejęcie obozu - ZAWSZE wykonaj, nie sprawdzaj ryzyka
			if DEBUG: print("AI %d: 🎯 %s ZAJMUJE OBÓZ %s!" % [team, unit_data.type, camp_pos])
			await execute_move(unit_data.unit, unit_data, camp_pos)
			if DEBUG: print("AI %d: ✅ OBÓZ PRZEJĘTY!" % team)
			return  # Obóz zdobyty, koniec!
		else:
			var best_move = find_move_towards_target(current_pos, moves, camp_pos)
			if best_move != Vector2i.ZERO:
				# Spearman idzie na obóz bez sprawdzania ryzyka
				# Knight/cavalry sprawdzają tylko pewne odcięcie (risk >= 0.9)
				var risk = evaluate_move_cutoff_risk(unit_data, best_move, state)
				if unit_data.type in ["knight", "cavalry"] and not risk.worth_it and risk.risk_level >= 0.9:
					if DEBUG: print("AI %d: ⚠️ %s wstrzymuje marsz (pewne odcięcie)" % [team, unit_data.type])
					var safe_move = find_safe_alternative_move(unit_data, best_move, state)
					if safe_move != Vector2i.ZERO:
						await execute_move(unit_data.unit, unit_data, safe_move)
					continue
				if DEBUG: print("AI %d: ⚔️ %s -> %s (atak na obóz)" % [team, unit_data.type, best_move])
				await execute_move(unit_data.unit, unit_data, best_move)
				await hex_grid.get_tree().create_timer(0.1).timeout

func surround_enemy(state: Dictionary, goal: Dictionary):
	"""Otacza wroga aby odciąć go od zamku"""
	var data = goal.data
	
	if data.type == "cutoff":
		# Użyj AKTUALNEGO stanu - wywołaj coordinate_cutoff_attack bezpośrednio
		# zamiast odtwarzać pre-obliczoną sekwencję (która może być nieaktualna)
		var enemy = data.enemy
		if not is_instance_valid(enemy.unit):
			if DEBUG: print("AI %d: surround_enemy - cel nieważny, pomijam" % team)
			return
		await coordinate_cutoff_attack(enemy, state)
	else:
		# Fallback - stary system
		if DEBUG: print("AI %d: Używam fallback surround" % team)

func expand_around_castle(state: Dictionary):
	"""Rozbudowuje terytorium - wysyła jednostki na GRANICĘ terytorium, nie przy zamku"""
	if state.my_castles.is_empty():
		return
	
	if DEBUG: print("AI %d: Rozbudowa wokół zamku" % team)
	
	# Znajdź pola na granicy własnego terytorium (neutralne/wrogie sąsiadujące z naszymi)
	var expansion_targets = []
	var seen = {}
	for hex_pos in state.my_connected_hexes:
		for nb in hex_grid.get_neighbors(hex_pos):
			if seen.has(nb): continue
			seen[nb] = true
			var owner = hex_grid.territory_map.get(nb, 0)
			if owner == 0 or (owner > 0 and owner != team):
				var hex = hex_grid.get_hex_at(nb)
				if hex and hex.occupied_object == null:
					expansion_targets.append(nb)
	
	if expansion_targets.is_empty():
		return
	
	# Wyślij farmerów i spearmanów - każdy na swój cel (nie wszyscy do jednego)
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		if expansion_targets.is_empty():
			break
		
		if unit_data.type in ["farmer", "spearman"]:
			var current_pos = unit_data.unit.hex_position
			var moves = get_possible_moves(unit_data.type, current_pos)
			# Użyj find_best_aggressive_move żeby uwzględnić grubość frontu
			var best_move = find_best_aggressive_move(unit_data, moves, state)
			
			if best_move != Vector2i.ZERO:
				if DEBUG: print("AI %d: %s rozbudowuje -> %s" % [team, unit_data.type, best_move])
				await execute_move(unit_data.unit, unit_data, best_move)

func expand_aggressively(state: Dictionary):
	"""Agresywna ekspansja - leapfrog: tylne jednostki wypełniają luki po przednich"""
	if DEBUG: print("AI %d: AGRESYWNA EKSPANSJA" % team)
	
	var units_to_move = []
	for unit_data in state.my_units:
		if is_instance_valid(unit_data.unit) and unit_data.unit not in hex_grid.units_moved_this_turn:
			units_to_move.append(unit_data)
	
	if units_to_move.is_empty():
		return
	
	# Sortuj: najpierw jednostki NAJBLIŻEJ WROGA (czołowe) - one idą pierwsze i wychodzą na ekspansję
	# Potem tylne mogą zająć pola które opuściły czołowe
	# To tworzy efekt "slinky" - łańcuch który przesuwa się do przodu
	units_to_move.sort_custom(func(a, b):
		var a_pos = a.unit.hex_position if is_instance_valid(a.unit) else a.pos
		var b_pos = b.unit.hex_position if is_instance_valid(b.unit) else b.pos
		
		# Policz ile pól expnsji ma każda jednostka
		var a_own = hex_grid.territory_map.get(a_pos, 0) == team
		var b_own = hex_grid.territory_map.get(b_pos, 0) == team
		
		# Jednostki na obcym/neutralnym terenie idą pierwsze (najbardziej wysunięte)
		if a_own != b_own:
			return not a_own  # nie-własne terytorium = wyższy priorytet
		
		# Wśród jednostek tego samego statusu - bliżej wroga idzie pierwsze
		var a_to_enemy = 999999
		var b_to_enemy = 999999
		for enemy in state.enemy_units:
			a_to_enemy = min(a_to_enemy, hex_distance(a_pos, enemy.pos))
			b_to_enemy = min(b_to_enemy, hex_distance(b_pos, enemy.pos))
		return a_to_enemy < b_to_enemy
	)
	
	for unit_data in units_to_move:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var current_pos = unit_data.unit.hex_position
		var moves = get_possible_moves(unit_data.type, current_pos)
		if moves.is_empty():
			if DEBUG: print("AI %d: UWAGA! %s na %s NIE MA RUCHÓW!" % [team, unit_data.type, current_pos])
			continue
		
		var best_move = find_best_aggressive_move(unit_data, moves, state)
		
		if best_move != Vector2i.ZERO:
			var risk = evaluate_move_cutoff_risk(unit_data, best_move, state)
			if not risk.worth_it:
				# Spearman: nigdy nie stoi - zawsze idzie do przodu na cel
				# Farmer: szuka bezpiecznej alternatywy
				if unit_data.type == "spearman":
					# Spearman ignoruje ryzyko odcięcia gdy ma cel wysokiej wartości
					# (zamek lub silna jednostka) - to jego rola
					if DEBUG: print("AI %d: ⚔️ spearman ignoruje ryzyko (%s) - atakuje!" % [team, risk.reason])
				else:
					if DEBUG: print("AI %d: ⚠️ %s: agresja zablokowana (%s) - szukam bezpiecznej pozycji" % [team, unit_data.type, risk.reason])
					var safe_move = find_safe_alternative_move(unit_data, best_move, state)
					if safe_move != Vector2i.ZERO:
						if DEBUG: print("AI %d: %s -> bezpieczna pozycja %s" % [team, unit_data.type, safe_move])
						await execute_move(unit_data.unit, unit_data, safe_move)
						continue
					# Farmer bez bezpiecznego ruchu też może iść jeśli ryzyko niskie
					if risk.risk_level >= 0.7:
						if DEBUG: print("AI %d: farmer STOI - zbyt ryzykowne (%.1f)" % [team, risk.risk_level])
						continue
			if DEBUG: print("AI %d: %s agresja -> %s" % [team, unit_data.type, best_move])
			await execute_move(unit_data.unit, unit_data, best_move)
		else:
			if DEBUG: print("AI %d: KARA! %s zmuszony do ruchu -> %s" % [team, unit_data.type, moves[0]])
			await execute_move(unit_data.unit, unit_data, moves[0])

func fortify_bottleneck(state: Dictionary, goal: Dictionary):
	"""Proaktywnie stawia mury na wąskich gardłach zanim wróg odtnie jednostki"""
	var candidates = goal.get("candidates", [])
	if candidates.is_empty():
		return
	
	var gold = hex_grid.get_selected_kingdom_gold(team)
	if gold < hex_grid.WALL_COST_PER_HEX:
		return
	
	# Wybierz najlepszego kandydata - jednostka z najmniejszą liczbą połączeń
	var best = candidates[0]
	var wall_pos = best.pos
	
	# Sprawdź czy ten hex nie ma już murów
	var walls_there = count_walls_around(wall_pos)
	if walls_there >= 6:
		# Znajdź innego kandydata
		for c in candidates:
			if count_walls_around(c.pos) < 6:
				wall_pos = c.pos
				break
			else:
				return  # Wszyscy kandydaci mają już mury
	
	if DEBUG: print("AI %d: 🔒 WĄSKIE GARDŁO @ %s - stawiam mury prewencyjnie!" % [team, wall_pos])
	var walls_created = hex_grid.create_hex_walls(wall_pos, team)
	if walls_created > 0:
		hex_grid.deduct_selected_kingdom_gold(team, hex_grid.WALL_COST_PER_HEX)
		if DEBUG: print("AI %d: Zbudowano %d murów na wąskim gardle" % [team, walls_created])

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
			
			var current_pos = unit_data.unit.hex_position
			var moves = get_possible_moves(unit_data.type, current_pos)
			var best_move = find_move_towards_target(current_pos, moves, threat_pos)
			
			if best_move != Vector2i.ZERO:
				await execute_move(unit_data.unit, unit_data, best_move)

func defend_castle_single_threat(state: Dictionary, goal: Dictionary):
	"""Broni zamku przed jednym konkretnym zagrożeniem (używane przez system goals)"""
	var enemy_pos = goal.get("enemy_pos", Vector2i.ZERO)
	if enemy_pos == Vector2i.ZERO:
		return
	
	# Znajdź zamek do obrony
	var castle_pos = state.my_castles[0] if not state.my_castles.is_empty() else Vector2i.ZERO
	
	# Wyślij TYLKO jednostkę która jest między wrogiem a zamkiem (nie cofa jednostek z frontu!)
	# Kryterium: jednostka jest bliżej wroga niż zamku (czyli jest "przed zamkiem")
	# LUB wróg jest bezpośrednio sąsiadem zamku (zagrożenie natychmiastowe)
	var immediate_threat = castle_pos != Vector2i.ZERO and hex_distance(enemy_pos, castle_pos) <= 2
	
	var best_unit = null
	var min_dist = 999999
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit) or unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		if unit_data.type in ["knight", "cavalry", "spearman"]:
			var current_pos = unit_data.unit.hex_position
			var dist_to_enemy = hex_distance(current_pos, enemy_pos)
			var dist_to_castle = hex_distance(current_pos, castle_pos) if castle_pos != Vector2i.ZERO else 0
			
			# Nie cofaj jednostki z frontu (jest bliżej wroga niż zamku = na froncie)
			# Cofaj TYLKO gdy jednostka jest za wrogiem (wróg jest bliżej zamku niż ona)
			# LUB gdy zagrożenie natychmiastowe
			var would_retreat = dist_to_castle > dist_to_enemy if castle_pos != Vector2i.ZERO else false
			if would_retreat and not immediate_threat:
				continue  # Pomiń - to by cofnęło jednostkę z frontu!
			
			if dist_to_enemy < min_dist:
				min_dist = dist_to_enemy
				best_unit = unit_data
	
	if best_unit != null:
		var current_pos = best_unit.unit.hex_position
		var moves = get_possible_moves(best_unit.type, current_pos)
		var best_move = find_move_towards_target(current_pos, moves, enemy_pos)
		if best_move != Vector2i.ZERO:
			if DEBUG: print("AI %d: %s broni zamku -> %s" % [team, best_unit.type, best_move])
			await execute_move(best_unit.unit, best_unit, best_move)

# ============================================================================
# MOVEMENT HELPERS
# ============================================================================

func find_move_towards_target(from: Vector2i, moves: Array, target: Vector2i) -> Vector2i:
	"""Znajduje ruch najbliżej celu"""
	var best_move = Vector2i.ZERO
	var min_dist = 999999
	
	for move in moves:
		var dist = hex_distance(move, target)
		if dist < min_dist:
			min_dist = dist
			best_move = move
	
	return best_move

func find_move_towards_targets(from: Vector2i, moves: Array, targets: Array) -> Vector2i:
	"""Znajduje ruch najbliżej któregokolwiek z celów"""
	var best_move = Vector2i.ZERO
	var min_dist = 999999
	
	for move in moves:
		for target in targets:
			var dist = hex_distance(move, target)
			if dist < min_dist:
				min_dist = dist
				best_move = move
	
	return best_move

func find_best_aggressive_move(unit_data: Dictionary, moves: Array, state: Dictionary) -> Vector2i:
	"""Znajduje najlepszy agresywny ruch z uwzględnieniem 'grubości frontu'.
	
	FILOZOFIA:
	- Farmer: ekspansja terytorium bezpieczna (min. 2 własnych sąsiadów po ruchu)
	- Spearman: atakuje zamki i silne jednostki, nie stoi
	- Wąskie gardło (1 połączenie po ruchu na wrogie pole) = duża kara, chyba że wróg nie może odciąć
	"""
	var best_move = Vector2i.ZERO
	var best_score = -999999
	
	var unit = unit_data.unit
	var already_moved_on_own = units_moved_on_own_territory.get(unit, false)
	
	# Zbierz pozycje sojuszników
	var ally_positions = {}
	for ally in state.my_units:
		if not is_instance_valid(ally.unit): continue
		var ally_current = ally.unit.hex_position
		if ally_current != (unit_data.unit.hex_position if is_instance_valid(unit_data.unit) else unit_data.pos):
			ally_positions[ally_current] = true
	
	var has_expansion_move = false
	for move in moves:
		if hex_grid.territory_map.get(move, 0) != team:
			has_expansion_move = true
			break
	
	# KLUCZOWE: Czy wróg ma jednostki mogące odciąć?
	# Jeśli nie ma → atakuj bezpośrednio, ignoruj kary za wąskie gardło
	var enemy_has_units = not state.enemy_units.is_empty()
	
	# Czy stać nas na mur przy wąskim gardle?
	# Mur = wystarczające zabezpieczenie zamiast czekania na grubość 2 hexów
	var gold = hex_grid.get_selected_kingdom_gold(team)
	var can_afford_wall = gold >= hex_grid.WALL_COST_PER_HEX
	
	# Dla spearmana: znajdź cele wysokiej wartości (zamki, silne jednostki)
	var spearman_targets = []
	if unit_data.type == "spearman":
		for coords in hex_grid.castle_map:
			if hex_grid.castle_map[coords].team != team and hex_grid.castle_map[coords].team != -1:
				spearman_targets.append(coords)
		for enemy in state.enemy_units:
			if enemy.type in ["knight", "cavalry", "spearman"]:
				spearman_targets.append(enemy.pos)
	
	for move in moves:
		var score = 0
		var owner = hex_grid.territory_map.get(move, 0)
		
		# --- SCORING BAZOWY wg właściciela ---
		if already_moved_on_own and owner == team and has_expansion_move:
			score -= 10000
		elif owner > 0 and owner != team:
			score += 80
		elif owner == 0:
			score += 60
		elif owner == team:
			score += (1 if not has_expansion_move else -50)
		
		# --- KLUCZOWE: "Grubość frontu" po wejściu na wrogie/neutralne pole ---
		# Policz ile własnych sąsiadów będzie miała jednostka po ruchu
		if owner != team:
			var own_neighbors_after = 0
			var enemy_neighbors_after = 0
			for nb in hex_grid.get_neighbors(move):
				var nb_owner = hex_grid.territory_map.get(nb, 0)
				if nb_owner == team:
					own_neighbors_after += 1
				elif nb_owner > 0 and nb_owner != team:
					enemy_neighbors_after += 1
			
			# Grubość frontu po wejściu na wrogie/neutralne pole
			if own_neighbors_after == 0:
				if not enemy_has_units:
					score -= 10  # Brak wrogich jednostek - prawie bez kary
				else:
					score -= 80  # Zupełnie oderwane - bardzo ryzykowne
			elif own_neighbors_after == 1:
				if not enemy_has_units:
					# Wróg bez jednostek - atakuj bezpośrednio
					score -= 5
				else:
					# Sprawdź czy wróg może faktycznie odciąć w 1 ruchu
					var can_be_cut = false
					for nb in hex_grid.get_neighbors(move):
						var nb_owner = hex_grid.territory_map.get(nb, 0)
						if nb_owner == team:
							for enemy in state.enemy_units:
								var enemy_moves = get_possible_moves(enemy.type, enemy.pos)
								if nb in enemy_moves:
									can_be_cut = true
									break
						if can_be_cut: break
					
					if can_be_cut:
						if can_afford_wall:
							score -= 15  # Mur wystarczy jako zabezpieczenie - mała kara
						else:
							score -= 60  # Wróg może odciąć i brak murów - silna kara
					else:
						score -= 10  # Wąskie gardło ale wróg nie dosięgnie
			elif own_neighbors_after == 2:
				score += 20  # Grubość 2 - bezpieczne, bonus
			elif own_neighbors_after >= 3:
				score += 40  # Szeroki front - bardzo bezpieczne, duży bonus
			
			# Bonus za wejście które "zaokrągla" terytorium (sąsiaduje z dwoma różnymi kawałkami własnego)
			# Wykryj czy to pole "łączy" dwa własne obszary
			if own_neighbors_after >= 2:
				# Sprawdź czy sąsiedzi własni są ze sobą połączeni (jeśli nie = to pole ich łączy)
				var own_nb_list = []
				for nb in hex_grid.get_neighbors(move):
					if hex_grid.territory_map.get(nb, 0) == team:
						own_nb_list.append(nb)
				if own_nb_list.size() >= 2:
					var first = own_nb_list[0]
					var connected_to_first = false
					for i in range(1, own_nb_list.size()):
						if own_nb_list[i] in hex_grid.get_neighbors(first):
							connected_to_first = true
							break
					if not connected_to_first:
						score += 30  # To pole łączy dwa oddzielne kawałki - priorytet!
		
		# --- Spearman: duży bonus za cele wysokiej wartości ---
		if unit_data.type == "spearman" and not spearman_targets.is_empty():
			var min_dist_to_target = 999999
			for t in spearman_targets:
				min_dist_to_target = min(min_dist_to_target, hex_distance(move, t))
			# Spearman aktywnie zmierza do zamku/silnej jednostki
			score += max(0, 50 - min_dist_to_target * 8)
		
		# --- Kara za stackowanie obok sojusznika ---
		if ally_positions.has(move):
			score -= 100
		
		var min_ally_dist = 999999
		for ally_pos in ally_positions:
			min_ally_dist = min(min_ally_dist, hex_distance(move, ally_pos))
		if min_ally_dist >= 2:
			score += 15
		elif min_ally_dist == 1:
			score -= 20
		
		# --- Bonus za bliskość do wrogów (agresja) ---
		if not state.enemy_units.is_empty():
			var min_enemy_dist = 999999
			for enemy in state.enemy_units:
				min_enemy_dist = min(min_enemy_dist, hex_distance(move, enemy.pos))
			score += max(0, 15 - min_enemy_dist * 2)
		
		if score > best_score:
			best_score = score
			best_move = move
	
	return best_move

func execute_move(unit, unit_data: Dictionary, target: Vector2i):
	"""Wykonuje ruch jednostki"""
	if not is_instance_valid(unit):
		return
	
	# NOWE: Sprawdź czy jednostka nie jest zamrożona
	if isolated_units_freeze.has(unit):
		var freeze_turn = isolated_units_freeze[unit]
		if hex_grid.current_round - freeze_turn < 1:
			if DEBUG: print("AI %d: %s zamrożona (odcięta w turze %d)" % [team, unit_data.type, freeze_turn])
			return  # NIE RUSZAJ SIĘ!
		else:
			# Minęła 1 tura - możesz się ruszyć
			isolated_units_freeze.erase(unit)
	
	# Używaj AKTUALNEJ pozycji jednostki, nie buforowanej unit_data.pos
	var from = unit.hex_position if is_instance_valid(unit) else unit_data.pos
	
	# NOWE: Sprawdź czy ruch jest po własnym terenie
	var target_owner = hex_grid.territory_map.get(target, 0)
	if target_owner == team:
		# Jednostka przeszła po swoim terenie - oznacz
		units_moved_on_own_territory[unit] = true
	
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
# UTILITY FUNCTIONS
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

func _get_connected_set() -> Dictionary:
	"""Zwraca pusty słownik - wymuszamy zawsze użycie _get_local_connected_territory per jednostkę.
	Dzięki temu AI nie myli królestw przy wielu zamkach."""
	return {}

func _get_local_connected_territory(start: Vector2i) -> Dictionary:
	"""Zwraca lokalnie połączone terytorium od pozycji startowej.
	Zatrzymuje się na granicach innych zamków (osobne królestwa)."""
	# Jeśli hex_grid ma get_connected_territories_for_unit, użyj go
	if hex_grid.has_method("get_connected_territories_for_unit"):
		var arr = hex_grid.get_connected_territories_for_unit(start, team)
		var result = {}
		for pos in arr:
			result[pos] = true
		return result
	
	# Fallback: stara logika flood fill
	var result = {}
	var visited = {}
	var queue = [start]
	visited[start] = true
	
	while not queue.is_empty():
		var current = queue.pop_front()
		
		if not hex_grid.hex_map.has(current):
			continue
		
		var owner = hex_grid.territory_map.get(current, 0)
		if owner != team:
			continue
		
		result[current] = true
		
		for neighbor in hex_grid.get_neighbors(current):
			if visited.get(neighbor, false):
				continue
			if not hex_grid.hex_map.has(neighbor):
				visited[neighbor] = true
				continue
			var neighbor_owner = hex_grid.territory_map.get(neighbor, 0)
			if neighbor_owner == team:
				visited[neighbor] = true
				queue.append(neighbor)
	
	return result

func get_farmer_moves(from: Vector2i) -> Array:
	"""
	Farmer może poruszać się po połączonym królestwie (głównym lub odłączonym) + pola graniczne.
	"""
	var moves = []
	var connected_set = _get_connected_set()
	
	# Sprawdź czy jednostka jest na głównym terytorium czy odłączonym
	var is_on_main_territory = connected_set.has(from)
	var local_territory = {}
	
	if is_on_main_territory:
		# Główne terytorium
		local_territory = connected_set
	else:
		# Odłączone terytorium - znajdź jego zasięg przez flood fill
		local_territory = _get_local_connected_territory(from)
		if local_territory.is_empty():
			return []  # Całkowicie odcięta jednostka bez terytorium
	
	# 1. Własne połączone terytorium (główne lub lokalne odłączone)
	for coords in local_territory:
		if coords == from:
			continue
		
		# KLUCZOWE: Sprawdź czy hex istnieje
		if not hex_grid.hex_map.has(coords):
			continue
		
		var hex = hex_grid.get_hex_at(coords)
		if not hex:
			continue
		if hex.occupied_object == null:
			moves.append(coords)
		# własny farmer blokuje ruch - nie dodawaj
	
	# 2. POLA GRANICZNE (wrogie lub neutralne) sąsiadujące z tym terytorium
	for coords in local_territory:
		var neighbors = hex_grid.get_neighbors(coords)
		for neighbor in neighbors:
			if neighbor in moves or neighbor == from:
				continue
			
			# KLUCZOWE: Sprawdź czy sąsiad istnieje
			if not hex_grid.hex_map.has(neighbor):
				continue
			
			var owner = hex_grid.territory_map.get(neighbor, 0)
			if owner == team:
				continue
			
			var hex = hex_grid.get_hex_at(neighbor)
			if not hex or hex.occupied_object != null:
				continue
			
			# Sprawdź czy można przejść (bez wrogich murów)
			var enemy_has_wall = false
			var neighbor_neighbors = hex_grid.get_neighbors(neighbor)
			var edge_index = neighbor_neighbors.find(coords)
			
			if edge_index != -1:
				var enemy_wall_key = "%d,%d-edge%d" % [neighbor.x, neighbor.y, edge_index]
				if hex_grid.wall_map.has(enemy_wall_key):
					var wall_data = hex_grid.wall_map[enemy_wall_key]
					if wall_data.get("team", 0) != team:
						enemy_has_wall = true
			
			if not enemy_has_wall:
				moves.append(neighbor)
	
	return moves

func get_spearman_moves(from: Vector2i) -> Array:
	"""Spearman porusza się po połączonym królestwie (głównym lub odłączonym) + atakuje sąsiednie wrogie pola"""
	var moves = []
	var connected_set = _get_connected_set()
	
	# Sprawdź czy jednostka jest na głównym terytorium czy odłączonym
	var is_on_main_territory = connected_set.has(from)
	var local_territory = {}
	
	if is_on_main_territory:
		local_territory = connected_set
	else:
		local_territory = _get_local_connected_territory(from)
		if local_territory.is_empty():
			return []
	
	# 1. POŁĄCZONE własne terytorium (główne lub lokalne)
	for coords in local_territory:
		if coords == from:
			continue
		
		# KLUCZOWE: Sprawdź czy hex istnieje
		if not hex_grid.hex_map.has(coords):
			continue
		
		var hex = hex_grid.get_hex_at(coords)
		if not hex:
			continue
		if hex.occupied_object == null:
			moves.append(coords)
		# własny spearman blokuje ruch - nie dodawaj
	
	# 2. ATAKI - sąsiednie wrogie pola
	var neighbors = hex_grid.get_neighbors(from)
	for neighbor in neighbors:
		# KLUCZOWE: Sprawdź czy sąsiad istnieje
		if not hex_grid.hex_map.has(neighbor):
			continue
		
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex:
			continue
		var owner = hex_grid.territory_map.get(neighbor, 0)
		var target = hex.occupied_object
		if owner != team:
			if target == null:
				# POPRAWKA: Spearman może przejąć pole z wallem (ale nie bez)
				moves.append(neighbor)
			elif target is Farmer or target is Spearman:  # DODANO: Spearman może atakować Spearman
				var target_team = get_object_team(target)
				if target_team != team:
					moves.append(neighbor)
			elif target is Castle:
				var target_team = get_object_team(target)
				if target_team != team:
					moves.append(neighbor)
	
	return moves

func get_knight_moves(from: Vector2i) -> Array:
	"""Knight porusza się po połączonym królestwie (głównym lub odłączonym) + atakuje sąsiednie wrogie pola"""
	var moves = []
	var connected_set = _get_connected_set()
	
	# Sprawdź czy jednostka jest na głównym terytorium czy odłączonym
	var is_on_main_territory = connected_set.has(from)
	var local_territory = {}
	
	if is_on_main_territory:
		local_territory = connected_set
	else:
		local_territory = _get_local_connected_territory(from)
		if local_territory.is_empty():
			return []
	
	# 1. POŁĄCZONE własne terytorium (główne lub lokalne)
	for coords in local_territory:
		if coords == from:
			continue
		
		# KLUCZOWE: Sprawdź czy hex istnieje
		if not hex_grid.hex_map.has(coords):
			continue
		
		var hex = hex_grid.get_hex_at(coords)
		if not hex:
			continue
		if hex.occupied_object == null:
			moves.append(coords)
		# własny knight blokuje ruch - nie dodawaj
	
	# 2. ATAKI - sąsiednie wrogie/neutralne pola
	var neighbors = hex_grid.get_neighbors(from)
	for neighbor in neighbors:
		# KLUCZOWE: Sprawdź czy sąsiad istnieje
		if not hex_grid.hex_map.has(neighbor):
			continue
		
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex:
			continue
		var owner = hex_grid.territory_map.get(neighbor, 0)
		var target = hex.occupied_object
		if owner != team:
			if target == null:
				if not is_blocked_by_wall(from, neighbor):
					moves.append(neighbor)
			elif target is Farmer or target is Spearman or target is Knight:  # DODANO: Knight może atakować Knight
				var target_team = get_object_team(target)
				if target_team != team:
					moves.append(neighbor)
			elif target is Castle:
				var target_team = get_object_team(target)
				if target_team != team:
					moves.append(neighbor)
	
	return moves

func get_cavalry_moves(from: Vector2i) -> Array:
	"""Cavalry - zasięg 2 pola, porusza się po połączonym królestwie (głównym lub odłączonym)"""
	var moves = []
	var connected_set = _get_connected_set()
	
	# Sprawdź czy jednostka jest na głównym terytorium czy odłączonym
	var is_on_main_territory = connected_set.has(from)
	var local_territory = {}
	
	if is_on_main_territory:
		local_territory = connected_set
	else:
		local_territory = _get_local_connected_territory(from)
		if local_territory.is_empty():
			return []
	
	# 1. POŁĄCZONE własne terytorium w zasięgu 2 (główne lub lokalne)
	for coords in local_territory:
		if coords == from:
			continue
		
		# KLUCZOWE: Sprawdź czy hex istnieje
		if not hex_grid.hex_map.has(coords):
			continue
		
		var dist = hex_distance(from, coords)
		if dist <= 2:
			var hex = hex_grid.get_hex_at(coords)
			if hex and hex.occupied_object == null:
				moves.append(coords)
	
	# 2. WROGIE CELE w zasięgu 2
	var range2_hexes = get_hexes_in_range_manual(from, 2)
	for target_pos in range2_hexes:
		if target_pos in moves:
			continue
		
		# KLUCZOWE: Sprawdź czy hex istnieje
		if not hex_grid.hex_map.has(target_pos):
			continue
		
		var dist = hex_distance(from, target_pos)
		if dist > 2 or dist < 1:
			continue
		
		var hex = hex_grid.get_hex_at(target_pos)
		if not hex:
			continue
		var owner = hex_grid.territory_map.get(target_pos, 0)
		var target = hex.occupied_object
		if owner == 0 or owner != team:
			if target == null:
				moves.append(target_pos)
			elif target is Farmer or target is Spearman or target is Knight or target is Cavalry or target is Castle:  # DODANO: Knight i Cavalry
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

func is_castle_undefended(castle_pos: Vector2i, castle_team: int) -> bool:
	"""
	Sprawdza czy zamek jest niebroniony i czy warto go atakować.
	Zamek jest uznany za cel tylko gdy:
	1. Nie ma jednostek przeciwnika bezpośrednio obok
	2. AI jest już blisko (≤ 5 hexów) - inaczej to nie "łatwy cel"
	"""
	
	# Sprawdź czy są jednostki bezpośrednio przy zamku
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
	
	# Zamek nie ma bezpośrednich obrońców - ale czy jesteśmy blisko?
	# Znajdź najbliższą jednostkę AI
	var min_dist = 999999
	
	# Sprawdź wszystkie jednostki AI
	for coords in hex_grid.knight_map:
		var unit = hex_grid.knight_map[coords]
		if is_instance_valid(unit) and unit.team == team:
			var dist = hex_distance(coords, castle_pos)
			if dist < min_dist:
				min_dist = dist
	
	for coords in hex_grid.farmer_map:
		var unit = hex_grid.farmer_map[coords]
		if is_instance_valid(unit) and unit.team == team:
			var dist = hex_distance(coords, castle_pos)
			if dist < min_dist:
				min_dist = dist
	
	for coords in hex_grid.spearman_map:
		var unit = hex_grid.spearman_map[coords]
		if is_instance_valid(unit) and unit.team == team:
			var dist = hex_distance(coords, castle_pos)
			if dist < min_dist:
				min_dist = dist
	
	for coords in hex_grid.cavalry_map:
		var unit = hex_grid.cavalry_map[coords]
		if is_instance_valid(unit) and unit.team == team:
			var dist = hex_distance(coords, castle_pos)
			if dist < min_dist:
				min_dist = dist
	
	if min_dist == 999999:
		return false  # Nie mamy jednostek
	
	# Zamek jest "niebroniony" tylko gdy AI jest już blisko (≤ 5 hexów)
	return min_dist <= 5

func get_min_distance(pos: Vector2i, targets: Array) -> int:
	if targets.is_empty():
		return 999999
	
	var min_dist = 999999
	for target in targets:
		var dist = hex_distance(pos, target)
		if dist < min_dist:
			min_dist = dist
	
	return min_dist

func get_min_unit_distance_to(target: Vector2i, units: Array) -> int:
	var min_dist = 999999
	for unit_data in units:
		var dist = hex_distance(unit_data.pos, target)
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
	
func find_bottleneck_to_target(target_pos: Vector2i, state: Dictionary) -> Vector2i:
	"""
	Znajduje wąskie gardło - pole które odcina drogę do celu
	"""
	var border = hex_grid.get_territory_border(team)
	var best_bottleneck = Vector2i.ZERO
	var min_distance_to_target = 999999
	
	for coords in border:
		var dist = hex_distance(coords, target_pos)
		
		# Czy przejęcie tego pola odcina dostęp?
		var neighbors = hex_grid.get_neighbors(target_pos)
		var access_count = 0
		var access_through_coords = false
		
		for n in neighbors:
			var owner = hex_grid.territory_map.get(n, 0)
			var target_team = get_object_team_at(target_pos)
			
			if owner == 0 or owner != target_team:
				access_count += 1
				if n == coords:
					access_through_coords = true
		
		# Jeśli to wąskie gardło
		if access_through_coords and access_count <= 3:
			if dist < min_distance_to_target:
				min_distance_to_target = dist
				best_bottleneck = coords
	
	return best_bottleneck

func coordinate_cutoff_attack(target: Dictionary, state: Dictionary) -> bool:
	"""
	Koordynuje wiele jednostek do odcięcia wroga.
	Jeśli nie można odciąć od razu - wysyła jednostki W KIERUNKU punktów odcięcia.
	"""
	var target_pos = target.pos
	var target_unit_type = target.type
	var target_strength = target.get("strength", 10)
	
	if DEBUG: print("AI %d: === KOORDYNOWANE ODCIĘCIE ===" % team)
	if DEBUG: print("AI %d: Cel: %s (siła: %d)" % [team, target_unit_type, target_strength])
	
	# Znajdź pola które trzeba zablokować
	var cutoff_points = find_multi_hex_cutoff(target_pos, state)
	
	if cutoff_points.is_empty():
		if DEBUG: print("AI %d: Nie znaleziono punktów odcięcia" % team)
		return false
	
	if DEBUG: print("AI %d: Punkty odcięcia: %s" % [team, cutoff_points])
	
	var needed = cutoff_points.size()
	
	# Zbierz wolne jednostki i sprawdź zasięg
	var units_in_range = []    # mogą dotrzeć DO punktu od razu
	var units_approaching = [] # mogą się zbliżyć (nie w zasięgu ale blisko)
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		if unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		if unit_data.type == "cavalry":
			var moves_done = hex_grid.cavalry_moves_this_turn.get(unit_data.unit, 0)
			if moves_done >= 2:
				continue
		
		var current_pos = unit_data.unit.hex_position
		var moves = get_possible_moves(unit_data.type, current_pos)
		
		var can_reach = false
		for cp in cutoff_points:
			if cp in moves:
				can_reach = true
				break
		
		if can_reach:
			units_in_range.append(unit_data)
		else:
			# Sprawdź czy jednostka jest blisko (może dojść za 1-2 tury)
			var min_dist = 999999
			for cp in cutoff_points:
				min_dist = min(min_dist, hex_distance(current_pos, cp))
			if min_dist <= 4:
				units_approaching.append(unit_data)
	
	if DEBUG: print("AI %d: Połączeń do zablokowania: %d, w zasięgu: %d, zbliżających się: %d" % [
		team, needed, units_in_range.size(), units_approaching.size()])
	
	# PRZYPADEK 1: Mamy wystarczająco jednostek - wykonaj pełne odcięcie
	if units_in_range.size() >= needed:
		return await _execute_cutoff_plan(cutoff_points, units_in_range, target_pos, needed)
	
	# PRZYPADEK 2: Nie mamy dość jednostek w zasięgu - przesuń wszystkich w kierunku
	# (zarówno te blisko jak i te dalej)
	var all_available = units_in_range + units_approaching
	if all_available.is_empty():
		if DEBUG: print("AI %d: Brak jednostek w pobliżu punktów odcięcia" % team)
		return false
	
	if DEBUG: print("AI %d: Niewystarczające odcięcie - przesuwam %d jednostek w kierunku celu" % [team, all_available.size()])
	
	# Przypisz każdą jednostkę do najbliższego punktu odcięcia i idź w jego kierunku
	var assigned_targets = {}  # unit -> target_cutoff_point
	var point_unit_count = {}  # cutoff_point -> ile jednostek zmierza w tym kierunku
	
	# Posortuj jednostki według odległości do najbliższego punktu (bliższe najpierw)
	all_available.sort_custom(func(a, b):
		var a_pos = a.unit.hex_position if is_instance_valid(a.unit) else a.pos
		var b_pos = b.unit.hex_position if is_instance_valid(b.unit) else b.pos
		var a_min = 999999
		var b_min = 999999
		for cp in cutoff_points:
			a_min = min(a_min, hex_distance(a_pos, cp))
			b_min = min(b_min, hex_distance(b_pos, cp))
		return a_min < b_min
	)
	
	var executed = 0
	for unit_data in all_available:
		if unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var current_pos = unit_data.unit.hex_position
		var moves = get_possible_moves(unit_data.type, current_pos)
		if moves.is_empty():
			continue
		
		# Znajdź najlepszy punkt odcięcia dla tej jednostki
		# Preferuj punkty które mają najmniej przypisanych jednostek
		var best_cp = Vector2i.ZERO
		var best_score = -999999
		for cp in cutoff_points:
			var dist = hex_distance(current_pos, cp)
			var assigned_count = point_unit_count.get(cp, 0)
			# Preferuj bliższe punkty z mniejszą liczbą przypisanych jednostek
			var score = -dist * 10 - assigned_count * 5
			if score > best_score:
				best_score = score
				best_cp = cp
		
		if best_cp == Vector2i.ZERO:
			continue
		
		# Idź w kierunku tego punktu (lub bezpośrednio jeśli w zasięgu)
		var best_move = Vector2i.ZERO
		if best_cp in moves:
			best_move = best_cp
		else:
			best_move = find_move_towards_target(current_pos, moves, best_cp)
		
		if best_move != Vector2i.ZERO:
			if DEBUG: print("AI %d: %s -> %s (zbliżam się do odcięcia @ %s)" % [team, unit_data.type, best_move, best_cp])
			await execute_move(unit_data.unit, unit_data, best_move)
			point_unit_count[best_cp] = point_unit_count.get(best_cp, 0) + 1
			executed += 1
	
	if DEBUG: print("AI %d: === KONIEC KOORDYNACJI (wykonano: %d ruchów) ===" % [team, executed])
	return executed > 0

func _execute_cutoff_plan(cutoff_points: Array, available_units: Array, target_pos: Vector2i, needed: int) -> bool:
	"""Wykonuje pełny plan odcięcia gdy mamy wystarczająco jednostek.
	Nadmiarowe jednostki (ponad needed) są kierowane na inne sąsiednie pola celu."""
	var attack_plan = []
	var assigned_units = []
	var assigned_targets = []  # które pola już zajęte w planie
	
	# FAZA 1: Przypisz jednostki do punktów odcięcia (required)
	for cutoff_point in cutoff_points:
		var best_unit = null
		var best_score = -999999
		
		for unit_data in available_units:
			if unit_data.unit in hex_grid.units_moved_this_turn:
				continue
			if unit_data in assigned_units:
				continue
			
			var current_pos = unit_data.unit.hex_position if is_instance_valid(unit_data.unit) else unit_data.pos
			var moves = get_possible_moves(unit_data.type, current_pos)
			
			if cutoff_point in moves:
				var dist_to_point = hex_distance(current_pos, cutoff_point)
				var dist_to_target = hex_distance(current_pos, target_pos)
				var score = 100 - dist_to_target + (10 - dist_to_point)
				if score > best_score:
					best_score = score
					best_unit = unit_data
		
		if best_unit != null:
			var current_pos_for_dist = best_unit.unit.hex_position if is_instance_valid(best_unit.unit) else best_unit.pos
			attack_plan.append({
				"unit": best_unit,
				"target": cutoff_point,
				"distance": hex_distance(current_pos_for_dist, cutoff_point)
			})
			assigned_units.append(best_unit)
			assigned_targets.append(cutoff_point)
	
	# FAZA 2: Nadmiarowe jednostki -> idą na inne sąsiednie pola celu (blokowanie ucieczki)
	# To zapobiega stackowaniu się za knightem
	var extra_targets = []
	for neighbor in hex_grid.get_neighbors(target_pos):
		if neighbor in assigned_targets:
			continue
		var owner = hex_grid.territory_map.get(neighbor, 0)
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex or hex.occupied_object != null:
			continue
		# Może być nasze lub neutralne - chcemy otaczać wroga
		extra_targets.append(neighbor)
	
	for unit_data in available_units:
		if unit_data in assigned_units:
			continue
		if unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		if extra_targets.is_empty():
			break
		
		var current_pos = unit_data.unit.hex_position if is_instance_valid(unit_data.unit) else unit_data.pos
		var moves = get_possible_moves(unit_data.type, current_pos)
		
		# Znajdź najbliższy niezajęty extra_target w zasięgu
		var best_extra = Vector2i.ZERO
		var best_dist = 999999
		for et in extra_targets:
			if et in moves:
				var d = hex_distance(current_pos, et)
				if d < best_dist:
					best_dist = d
					best_extra = et
		
		if best_extra != Vector2i.ZERO:
			var dist = hex_distance(current_pos, best_extra)
			attack_plan.append({
				"unit": unit_data,
				"target": best_extra,
				"distance": dist
			})
			assigned_units.append(unit_data)
			extra_targets.erase(best_extra)
	
	if attack_plan.is_empty():
		return false
	
	attack_plan.sort_custom(func(a, b): return a.distance < b.distance)
	if DEBUG: print("AI %d: Plan odcięcia - jednostek: %d (wymagane: %d)" % [team, attack_plan.size(), needed])
	
	var executed_moves = 0
	for i in range(min(attack_plan.size(), 4)):
		var action = attack_plan[i]
		var unit = action.unit
		var target_move = action.target
		
		if unit.unit in hex_grid.units_moved_this_turn:
			continue
		
		if DEBUG: print("AI %d: [RUCH %d] %s @ %s -> %s" % [team, i+1, unit.type, unit.unit.hex_position, target_move])
		
		var current_from = unit.unit.hex_position if is_instance_valid(unit.unit) else unit.pos
		if await execute_unit_move(unit.type, current_from, target_move):
			executed_moves += 1
			if unit.type != "cavalry":
				unit.moved = true
			else:
				var moves_done = hex_grid.cavalry_moves_this_turn.get(unit.unit, 0)
				if moves_done >= 2:
					unit.moved = true
	
	if DEBUG: print("AI %d: === KONIEC KOORDYNACJI (wykonano: %d ruchów) ===" % [team, executed_moves])
	return executed_moves > 0
	
func execute_unit_move(unit_type: String, from: Vector2i, to: Vector2i) -> bool:
	"""Wykonuje ruch jednostki"""
	await hex_grid.get_tree().create_timer(0.1).timeout
	
	match unit_type:
		"farmer":
			if hex_grid.farmer_map.has(from):
				hex_grid.move_farmer(from, to)
				return true
		"knight":
			if hex_grid.knight_map.has(from):
				hex_grid.move_knight(from, to)
				return true
		"spearman":
			if hex_grid.spearman_map.has(from):
				hex_grid.move_spearman(from, to)
				return true
		"cavalry":
			if hex_grid.cavalry_map.has(from):
				hex_grid.move_cavalry(from, to)
				return true
	
	return false

func get_object_team_at(pos: Vector2i) -> int:
	"""Zwraca team obiektu na pozycji"""
	if hex_grid.knight_map.has(pos):
		return hex_grid.knight_map[pos].team
	if hex_grid.farmer_map.has(pos):
		return hex_grid.farmer_map[pos].team
	if hex_grid.spearman_map.has(pos):
		return hex_grid.spearman_map[pos].team
	if hex_grid.cavalry_map.has(pos):
		return hex_grid.cavalry_map[pos].team
	if hex_grid.castle_map.has(pos):
		return hex_grid.castle_map[pos].team
	return 0
	
func find_multi_hex_cutoff(target_pos: Vector2i, state: Dictionary) -> Array:
	"""
	Znajduje pola ktore musimy zajac zeby odciac wroga od jego terytorium.
	
	Kluczowa zasada: polaczenie wroga z terytorium = pole NALEZACE DO JEGO TEAMU
	ktore sasiaduje z jego jednostka. Jesli zajmiemy to pole, przestaje byc jego
	terytorium i polaczenie znika.
	
	Wiec punkty odciecia = sasiednie pola wroga nalezace do jego teamu,
	KTORE MOZEMY ZAJAC (sa puste i dostepne dla naszych jednostek).
	"""
	var target_team = get_object_team_at(target_pos)
	if target_team <= 0:
		return []
	
	var cutoff_points = []
	
	# Punkty odciecia = pola terytorium wroga sasiadujace z jego jednostka
	# Zajecie ich = odciecie polaczenia
	for neighbor in hex_grid.get_neighbors(target_pos):
		if hex_grid.territory_map.get(neighbor, 0) != target_team:
			continue
		
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex:
			continue
		
		# Pole musi byc puste lub zajete przez nasza jednostke (ktora juz blokuje)
		if hex.occupied_object != null:
			# Nasza jednostka - to polaczenie juz zablokowane, nie trzeba tu isc
			if has_team(hex.occupied_object) and hex.occupied_object.team == team:
				continue  # Juz zablokowane - nie dodawaj do listy
			# Wroga jednostka lub zamek - nie mozemy wejsc
			continue
		
		# Puste pole terytorium wroga - mozemy je zajac i zerwac polaczenie
		cutoff_points.append(neighbor)
	
	# Sortuj po odleglosci od celu (najblizsze pierwsze)
	cutoff_points.sort_custom(func(a, b):
		return hex_distance(a, target_pos) < hex_distance(b, target_pos)
	)
	
	return cutoff_points

# ============================================================================
# BANDIT AI
# ============================================================================

func find_cutoff_threats(state: Dictionary) -> Array:
	"""Wykrywa zagrożenia odcięcia naszych własnych jednostek przez wrogów"""
	var threats = []
	
	# Dla każdej naszej jednostki sprawdź czy może zostać odcięta
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		
		var unit_pos = unit_data.pos
		
		# Zlicz połączenia z głównym terytorium
		var connections_to_main = 0
		var connection_points = []
		var neighbors = hex_grid.get_neighbors(unit_pos)
		
		for neighbor in neighbors:
			var owner = hex_grid.territory_map.get(neighbor, 0)
			if owner == team:
				# To jest nasze połączenie
				connections_to_main += 1
				connection_points.append(neighbor)
		
		# Jeśli mamy 1-2 połączenia - ryzyko odcięcia
		if connections_to_main >= 1 and connections_to_main <= 2:
			# Sprawdź czy wrogowie mogą zająć te punkty połączenia
			var vulnerable_connections = []
			
			for conn_point in connection_points:
				# Znajdź wrogie jednostki które mogą zagrozić temu połączeniu
				for enemy in state.enemy_units:
					# Sprawdź czy wróg może dotrzeć do sąsiadów tego połączenia
					var conn_neighbors = hex_grid.get_neighbors(conn_point)
					
					for cn in conn_neighbors:
						if cn == unit_pos:
							continue
						
						var dist = hex_distance(enemy.pos, cn)
						
						# Wróg w zasięgu 1-2 może zagrozić
						if dist <= 2:
							vulnerable_connections.append({
								"connection_point": conn_point,
								"threat_position": cn,
								"enemy": enemy,
								"distance": dist
							})
			
			if not vulnerable_connections.is_empty():
				threats.append({
					"unit": unit_data,
					"unit_pos": unit_pos,
					"connections": connections_to_main,
					"vulnerable_points": vulnerable_connections,
					"priority": 150 + unit_data.strength  # Wyższy dla silniejszych jednostek
				})
	
	# Sortuj według priorytetu
	threats.sort_custom(func(a, b): return a.priority > b.priority)
	
	if not threats.is_empty():
		if DEBUG: print("AI %d: WYKRYTO %d zagrożeń odcięcia naszych jednostek!" % [team, threats.size()])
		for threat in threats:
			print("  - %s @ %s (połączeń: %d, zagrożeń: %d)" % 
				[threat.unit.type, threat.unit_pos, threat.connections, threat.vulnerable_points.size()])
	
	return threats

func execute_bandit_turn(state: Dictionary):
	"""AI dla bandytów - preferują pola królestw (kradzież złota), mogą też chodzić po neutralnych"""
	if DEBUG: print("AI Bandytów: Ruszam %d jednostek" % state.my_units.size())
	
	if hex_grid.ui_manager:
		hex_grid.ui_manager.set_buttons_enabled(false)
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		if unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var bandit_spawn_round = unit_data.unit.get("spawn_turn")
		if bandit_spawn_round != null and bandit_spawn_round >= hex_grid.current_round - 1:
			if DEBUG: print("Bandyta @ %s pominięty - właśnie się zrespił (spawn: %d, current: %d)" % [unit_data.pos, bandit_spawn_round, hex_grid.current_round])
			continue
		
		var current_pos = unit_data.unit.hex_position
		var all_moves = get_bandit_moves(current_pos)
		
		if all_moves.is_empty():
			continue
		
		# PREFERUJ pola królestw (team > 0) — kradną złoto
		# Jeśli bandyta już stoi na polu królestwa i jest tam co rundę — pozostań jeśli brak lepszej opcji
		var kingdom_moves = []
		var neutral_moves = []
		var bandit_moves_list = []
		
		for move in all_moves:
			var owner = hex_grid.territory_map.get(move, 0)
			if owner > 0 and owner <= 4:
				kingdom_moves.append(move)
			elif owner == 0:
				neutral_moves.append(move)
			else:
				bandit_moves_list.append(move)
		
		var chosen_move: Vector2i
		
		if not kingdom_moves.is_empty():
			# Idź na pole królestwa (losowy jeśli wiele)
			chosen_move = kingdom_moves[randi() % kingdom_moves.size()]
		elif not neutral_moves.is_empty():
			# Brak pól królestwa - idź na neutralne
			chosen_move = neutral_moves[randi() % neutral_moves.size()]
		else:
			# Tylko pola bandyckie - losowy ruch
			chosen_move = bandit_moves_list[randi() % bandit_moves_list.size()]
		
		if DEBUG: print("Bandyta: %s -> %s (owner: %d)" % [current_pos, chosen_move, hex_grid.territory_map.get(chosen_move, 0)])
		await execute_move(unit_data.unit, unit_data, chosen_move)
		await hex_grid.get_tree().create_timer(0.1).timeout
	
	if hex_grid.ui_manager:
		hex_grid.ui_manager.set_buttons_enabled(true)

func get_bandit_moves(from: Vector2i) -> Array:
	"""Ruchy bandytów - po swoich i neutralnych polach, mogą zajmować wrogie puste pola"""
	var moves = []
	var neighbors = hex_grid.get_neighbors(from)
	
	for neighbor in neighbors:
		var hex = hex_grid.get_hex_at(neighbor)
		if not hex:
			continue
		
		var owner = hex_grid.territory_map.get(neighbor, 0)
		var target = hex.occupied_object
		
		# Może iść na:
		# 1. Własne pola bandytów (team -1)
		# 2. Neutralne pola (owner 0)
		# 3. Wrogie pola BEZ jednostek i murów
		if owner == -1:
			# Własne terytorium bandytów
			if target == null or (target is Farmer and target.team == -1):
				moves.append(neighbor)
		elif owner == 0:
			# Neutralne pola - może zajmować
			if target == null:
				moves.append(neighbor)
		elif owner > 0 and owner <= 4:
			# Wrogie pole - może zająć tylko jeśli puste i bez murów
			if target == null:
				# Sprawdź czy nie ma muru
				if not hex_grid.has_wall_between(from, neighbor):
					moves.append(neighbor)
	
	return moves

func force_stagnant_units_to_attack(state: Dictionary):
	"""Wymusza atak dla jednostek kręcących się po własnym terenie > 2 tury"""
	var connected_territory = hex_grid.get_connected_territories(team)
	var connected_set = {}
	for pos in connected_territory:
		connected_set[pos] = true
	
	for unit_data in state.my_units:
		if not is_instance_valid(unit_data.unit):
			continue
		if unit_data.unit in hex_grid.units_moved_this_turn:
			continue
		
		var unit = unit_data.unit
		var unit_pos = unit.hex_position
		var last_pos = unit_last_positions.get(unit, unit_pos)
		
		# Sprawdź czy jednostka jest na własnym terenie
		var is_on_own = connected_set.has(unit_pos)
		
		if is_on_own and unit_pos == last_pos:
			# Jednostka stoi w miejscu na własnym terenie
			var turns_idle = unit_own_territory_turns.get(unit, 0) + 1
			unit_own_territory_turns[unit] = turns_idle
			
			if turns_idle >= 2:
				# Wymuś ruch na wrogie lub neutralne
				var forced = await force_unit_to_enemy_territory(unit, unit_data.type, state)
				if forced:
					unit_own_territory_turns[unit] = 0
		else:
			unit_own_territory_turns[unit] = 0
		
		unit_last_positions[unit] = unit_pos

func force_unit_to_enemy_territory(unit, unit_type: String, state: Dictionary) -> bool:
	"""Rusza jednostkę na najbliższe wrogie lub neutralne pole"""
	var unit_pos = unit.hex_position
	
	# Znajdź najbliższe wrogie/neutralne pole
	var best_target = Vector2i(-999, -999)
	var best_dist = 999
	
	for coords in hex_grid.hex_map:
		var owner = hex_grid.territory_map.get(coords, 0)
		if owner != team:  # Wrogie lub neutralne
			var dist = hex_distance(unit_pos, coords)
			if dist < best_dist and dist <= 2:
				best_dist = dist
				best_target = coords
	
	if best_target == Vector2i(-999, -999):
		return false
	
	# Spróbuj ruszyć jednostkę
	var neighbors = hex_grid.get_neighbors(unit_pos)
	var best_step = Vector2i(-999, -999)
	var best_step_dist = 999
	
	for nb in neighbors:
		if not hex_grid.hex_map.has(nb):
			continue
		var owner = hex_grid.territory_map.get(nb, 0)
		if owner == team:
			continue  # Nie cofaj na własne
		var dist = hex_distance(nb, best_target)
		if dist < best_step_dist:
			best_step_dist = dist
			best_step = nb
	
	if best_step == Vector2i(-999, -999):
		return false
	
	# Wykonaj ruch
	if hex_grid.has_method("move_unit"):
		hex_grid.move_unit(unit, best_step)
		return true
	
	return false
	
func has_all_walls_on_hex(pos: Vector2i) -> bool:
	"""Sprawdza czy hex ma już wszystkie 6 ścian przez wall_map"""
	for i in range(6):
		var edge_key = "%d,%d-edge%d" % [pos.x, pos.y, i]
		if not hex_grid.wall_map.has(edge_key):
			return false
	return true
	
func is_castle_reachable(from: Vector2i, castle_pos: Vector2i) -> bool:
	"""Sprawdza czy zamek jest osiągalny przez połączone terytorium (flood fill)"""
	var visited = {}
	var queue = [from]
	visited[from] = true
	var head = 0
	
	while head < queue.size():
		var current = queue[head]
		head += 1
		
		if current == castle_pos:
			return true
		
		for neighbor in hex_grid.get_neighbors(current):
			if visited.has(neighbor):
				continue
			if not hex_grid.hex_map.has(neighbor):
				continue
			# Można przejść przez własne terytorium, neutralne lub wrogie (ale nie przepaście)
			visited[neighbor] = true
			queue.append(neighbor)
	
	return false
