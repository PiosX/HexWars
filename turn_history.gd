extends Node
class_name TurnHistory

# Historia snapshottów (max 50 tur wstecz dla bezpieczeństwa)
var snapshots: Array = []
const MAX_SNAPSHOTS = 50

# USUNIĘTE: Nie używamy już lokalnego licznika rewindów
# Teraz korzystamy z global_time_currency z Main

func _init():
	snapshots.clear()

func can_rewind() -> bool:
	"""Sprawdza czy można cofnąć turę"""
	var main = get_node_or_null("/root/Main")
	if not main:
		return false
	return main.get_currency() > 0 and snapshots.size() >= 2

func get_rewinds_remaining() -> int:
	"""Zwraca aktualną ilość waluty (używaną jako rewindy)"""
	var main = get_node_or_null("/root/Main")
	if not main:
		return 0
	return main.get_currency()

func save_turn_snapshot(hex_grid) -> void:
	"""Zapisuje snapshot stanu gry na koniec tury"""
	
	var snapshot = {
		"round": hex_grid.current_round,
		"team": hex_grid.current_team,
		"team_gold": hex_grid.team_gold.duplicate(),
		"territory_map": hex_grid.territory_map.duplicate(),
		"team_territory_count": hex_grid.team_territory_count.duplicate(),
		
		# Jednostki - zapisujemy pozycje i teamy
		"knights": _serialize_units(hex_grid.knight_map),
		"farmers": _serialize_units(hex_grid.farmer_map),
		"spearmen": _serialize_units(hex_grid.spearman_map),
		"cavalry": _serialize_units(hex_grid.cavalry_map),
		"castles": _serialize_units(hex_grid.castle_map),
		
		# Mury - zapisujemy dane wall_map
		"walls": _serialize_walls(hex_grid.wall_map),
		
		# Stany jednostek
		"units_moved": [],
		"cavalry_moves": {}
	}
	
	# Dodaj snapshot na koniec listy
	snapshots.append(snapshot)
	
	# Ogranicz rozmiar historii
	if snapshots.size() > MAX_SNAPSHOTS:
		snapshots.pop_front()
	
	print("=== SNAPSHOT ZAPISANY ===")
	print("Runda: ", snapshot.round, " | Drużyna: ", snapshot.team)
	print("Snapshottów w historii: ", snapshots.size())

func restore_previous_turn(hex_grid) -> bool:
	"""Przywraca stan z poprzedniej tury - KOSZTUJE 1 WALUTĘ"""
	
	if not can_rewind():
		print("Brak dostępnych cofnięć (brak waluty)!")
		return false
	
	if snapshots.is_empty():
		print("Brak snapshottów do przywrócenia!")
		return false
	
	# Usuń ostatni snapshot (aktualny stan)
	var snapshot = snapshots.pop_back()
	
	if snapshots.is_empty():
		print("To była pierwsza tura - nie można cofnąć dalej!")
		snapshots.append(snapshot)  # Przywróć snapshot
		return false
	
	# Pobierz poprzedni snapshot
	var previous = snapshots[snapshots.size() - 1]
	
	var main = get_node("/root/Main")
	print("=== COFANIE TURY ===")
	print("Z rundy ", hex_grid.current_round, " do rundy ", previous.round)
	print("Cofnięć pozostało: ", main.get_currency() - 1)
	
	# Wyczyść aktualny stan
	_clear_current_state(hex_grid)
	
	# Przywróć stan z snapshota
	_restore_state(hex_grid, previous)
	
	# Zmniejsz walutę o 1
	if not main.spend_currency(1):
		print("ERROR: Nie udało się zużyć waluty!")
		return false
	
	print("=== TURA COFNIĘTA (pozostało waluty: %d) ===" % main.get_currency())
	return true

func restore_multiple_turns(hex_grid, num_turns: int, rewinds_cost: int = 1) -> bool:
	"""Cofa wiele tur naraz (np. dla defeat popup)
	num_turns - ile tur cofnąć
	rewinds_cost - ile waluty zużyć (domyślnie 1, ale defeat popup używa 2)"""
	
	var main = get_node_or_null("/root/Main")
	if not main:
		print("ERROR: Brak dostępu do Main!")
		return false
	
	if main.get_currency() < rewinds_cost:
		print("Nie wystarczająco waluty! Potrzeba: %d, masz: %d" % [rewinds_cost, main.get_currency()])
		return false
	
	if snapshots.size() < num_turns + 1:
		print("Za mało snapshottów w historii! Potrzeba: %d, masz: %d" % [num_turns + 1, snapshots.size()])
		return false
	
	print("=== COFANIE %d TUR (koszt: %d waluty) ===" % [num_turns, rewinds_cost])
	
	# Usuń N ostatnich snapshottów
	for i in range(num_turns):
		snapshots.pop_back()
	
	# Pobierz snapshot do którego wracamy
	var target = snapshots[snapshots.size() - 1]
	
	print("Cofanie do rundy %d, team %d" % [target.round, target.team])
	
	# Wyczyść aktualny stan
	_clear_current_state(hex_grid)
	
	# Przywróć stan z snapshota
	await _restore_state(hex_grid, target)
	
	# Zmniejsz walutę
	if not main.spend_currency(rewinds_cost):
		print("ERROR: Nie udało się zużyć waluty!")
		return false
	
	print("=== COFNIĘTO %d TUR (pozostało waluty: %d) ===" % [num_turns, main.get_currency()])
	return true

func _serialize_units(unit_map: Dictionary) -> Dictionary:
	"""Serializuje mapę jednostek (coords -> team)"""
	var serialized = {}
	
	for coords in unit_map:
		var unit = unit_map[coords]
		serialized[coords] = unit.team
	
	return serialized

func _serialize_walls(wall_map: Dictionary) -> Dictionary:
	"""Serializuje mury (edge_key -> wall_data)"""
	var serialized = {}
	
	for edge_key in wall_map:
		var wall_data = wall_map[edge_key]
		serialized[edge_key] = wall_data.duplicate()
	
	return serialized

func _clear_current_state(hex_grid) -> void:
	"""Usuwa wszystkie jednostki i mury z planszy"""
	
	# Usuń wszystkie jednostki
	for coords in hex_grid.knight_map.keys():
		hex_grid.remove_knight_at(coords)
	
	for coords in hex_grid.farmer_map.keys():
		hex_grid.remove_farmer_at(coords)
	
	for coords in hex_grid.spearman_map.keys():
		hex_grid.remove_spearman_at(coords)
	
	for coords in hex_grid.cavalry_map.keys():
		hex_grid.remove_cavalry_at(coords)
	
	for coords in hex_grid.castle_map.keys():
		hex_grid.remove_castle_at(coords)
	
	# Usuń wszystkie mury wizualne
	if hex_grid.has_meta("wall_lines"):
		var wall_lines = hex_grid.get_meta("wall_lines")
		for key in wall_lines:
			if wall_lines[key]:
				wall_lines[key].queue_free()
		wall_lines.clear()
	
	# Wyczyść mapy
	hex_grid.knight_map.clear()
	hex_grid.farmer_map.clear()
	hex_grid.spearman_map.clear()
	hex_grid.cavalry_map.clear()
	hex_grid.castle_map.clear()
	hex_grid.wall_map.clear()
	hex_grid.territory_map.clear()
	hex_grid.units_moved_this_turn.clear()
	hex_grid.cavalry_moves_this_turn.clear()

func _restore_state(hex_grid, snapshot: Dictionary) -> void:
	"""Przywraca stan gry ze snapshota"""
	
	# Przywróć podstawowe wartości
	hex_grid.current_round = snapshot.round
	hex_grid.current_team = snapshot.team
	hex_grid.team_gold = snapshot.team_gold.duplicate()
	hex_grid.territory_map = snapshot.territory_map.duplicate()
	hex_grid.team_territory_count = snapshot.team_territory_count.duplicate()
	
	# NAJPIERW przywróć zamki (muszą być przed update_hex_color)
	for coords in snapshot.castles:
		var team = snapshot.castles[coords]
		hex_grid.place_castle_at(coords, team)
	
	# POTEM przywróć kolory terytoriów (po zamkach!)
	for coords in hex_grid.territory_map:
		hex_grid.update_hex_color(coords)
	
	# Przywróć neutralne pola (te które NIE są w territory_map)
	for coords in hex_grid.hex_map:
		if not hex_grid.territory_map.has(coords):
			hex_grid.update_hex_color(coords)
	
	# Przywróć jednostki
	for coords in snapshot.knights:
		var team = snapshot.knights[coords]
		hex_grid.place_knight_at(coords, team)
	
	for coords in snapshot.farmers:
		var team = snapshot.farmers[coords]
		hex_grid.place_farmer_at(coords, team)
	
	for coords in snapshot.spearmen:
		var team = snapshot.spearmen[coords]
		hex_grid.place_spearman_at(coords, team)
	
	for coords in snapshot.cavalry:
		var team = snapshot.cavalry[coords]
		hex_grid.place_cavalry_at(coords, team)
	
	# Przywróć mury
	hex_grid.wall_map = snapshot.walls.duplicate()
	_restore_walls_visual(hex_grid)
	
	# Resetuj stany
	hex_grid.units_moved_this_turn.clear()
	hex_grid.cavalry_moves_this_turn.clear()
	hex_grid.selected_unit = null
	hex_grid.clear_highlights()
	
	# Odśwież UI
	hex_grid.update_ui()
	
	# Poczekaj chwilę aż wszystkie obiekty się załadują
	await hex_grid.get_tree().create_timer(0.05).timeout
	
	# WAŻNE: Wymuś odświeżenie kolorów WSZYSTKICH hexów PO załadowaniu
	# To naprawia problem z "duchowymi" kolorami po rewind
	for coords in hex_grid.hex_map.keys():
		hex_grid.update_hex_color(coords)
	
	await hex_grid.get_tree().create_timer(0.05).timeout
	hex_grid.pulse_available_units()

func _restore_walls_visual(hex_grid) -> void:
	"""Odtwarza wizualne reprezentacje murów"""
	
	if not hex_grid.has_meta("wall_lines"):
		hex_grid.set_meta("wall_lines", {})
	
	var wall_lines = hex_grid.get_meta("wall_lines")
	
	for edge_key in hex_grid.wall_map:
		var wall_data = hex_grid.wall_map[edge_key]
		var hex_coords = wall_data.hex
		var edge_index = wall_data.edge
		
		# Oblicz pozycje wierzchołków
		var center = hex_grid.hex_to_pixel(hex_coords)
		var hex_radius = hex_grid.hex_width * 0.45
		var angles = [30, 90, 150, 210, 270, 330]
		var vertices = []
		
		for angle in angles:
			var rad = deg_to_rad(angle)
			var x = center.x + hex_radius * cos(rad)
			var y = center.y + hex_radius * sin(rad)
			vertices.append(Vector2(x, y))
		
		var start = vertices[edge_index]
		var end = vertices[(edge_index + 1) % vertices.size()]
		
		# Stwórz wizualną linię
		var wall_line = WallLine.new()
		wall_line.z_index = 10
		wall_line.setup(start, end, Color.WHITE, 2.5, false)
		hex_grid.add_child(wall_line)
		
		wall_lines[edge_key] = wall_line

func reset_rewinds() -> void:
	"""Resetuje snapshoty (np. na początku nowej gry)
	Waluta nie jest resetowana - jest zarządzana przez Main"""
	snapshots.clear()
	print("Historia tur wyczyszczona")
