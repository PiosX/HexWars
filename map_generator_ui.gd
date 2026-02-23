extends CanvasLayer
class_name MapGeneratorUI

# Panel generatora losowych map – F9

var hex_grid: HexGrid

var panel: Panel
var info_label: Label
var size_option: OptionButton
var kingdoms_option: OptionButton
var neutral_checkbox: CheckBox
var blank_map_checkbox: CheckBox
var generate_btn: Button
var clear_btn: Button
var restyle_kingdoms_option: OptionButton
var restyle_density_option: OptionButton
var restyle_btn: Button

const SIZE_RANGES = {
	0: {"w_min": 7,  "w_max": 14, "h_min": 6,  "h_max": 12},
	1: {"w_min": 13, "w_max": 22, "h_min": 10, "h_max": 18},
	2: {"w_min": 20, "w_max": 30, "h_min": 16, "h_max": 25},
}

# ============================================================
# UI
# ============================================================

func _ready():
	visible = false
	layer = 101

	panel = Panel.new()
	panel.custom_minimum_size = Vector2(380, 780)
	panel.position = Vector2(10, 50)
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "🗺️ GENERATOR MAP"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	info_label = Label.new()
	info_label.text = "F9 aby pokazać/ukryć"
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info_label)

	_add_sep(vbox)
	_add_label(vbox, "📐 Rozmiar mapy:", 14)

	size_option = OptionButton.new()
	size_option.custom_minimum_size = Vector2(0, 34)
	size_option.add_item("Small  (7-14 × 6-12)")
	size_option.add_item("Medium (13-22 × 10-18)")
	size_option.add_item("Large  (20-30 × 16-25)")
	size_option.selected = 1
	vbox.add_child(size_option)

	_add_sep(vbox)
	_add_label(vbox, "👑 Liczba królestw:", 14)

	kingdoms_option = OptionButton.new()
	kingdoms_option.custom_minimum_size = Vector2(0, 34)
	kingdoms_option.add_item("2 (Niebieski, Czerwony)")
	kingdoms_option.add_item("3 (bez Żółtego)")
	kingdoms_option.add_item("4 (wszystkie kolory)")
	kingdoms_option.selected = 2
	vbox.add_child(kingdoms_option)

	_add_sep(vbox)
	_add_label(vbox, "⚙️ Opcje:", 14)

	neutral_checkbox = CheckBox.new()
	neutral_checkbox.text = "Kolonizacja (dużo pustych hexów)"
	neutral_checkbox.button_pressed = false
	vbox.add_child(neutral_checkbox)

	blank_map_checkbox = CheckBox.new()
	blank_map_checkbox.text = "Czysta mapa (3 hexy + zamek + farmer per królestwo)"
	blank_map_checkbox.button_pressed = false
	blank_map_checkbox.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(blank_map_checkbox)

	_add_sep(vbox)

	generate_btn = Button.new()
	generate_btn.text = "🎲 GENERUJ MAPĘ"
	generate_btn.custom_minimum_size = Vector2(0, 46)
	generate_btn.add_theme_font_size_override("font_size", 17)
	generate_btn.pressed.connect(_on_generate)
	vbox.add_child(generate_btn)

	var sp = Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(sp)

	clear_btn = Button.new()
	clear_btn.text = "🗑️ Wyczyść mapę (od zera)"
	clear_btn.custom_minimum_size = Vector2(0, 34)
	clear_btn.pressed.connect(_on_clear_map)
	vbox.add_child(clear_btn)

	_add_sep(vbox)
	_add_label(vbox, "🔧 Dostosuj istniejącą mapę:", 14)

	var hint = Label.new()
	hint.text = "Zmienia kolory/zagęszczenie na istniejącej mapie."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	restyle_kingdoms_option = OptionButton.new()
	restyle_kingdoms_option.custom_minimum_size = Vector2(0, 32)
	restyle_kingdoms_option.add_item("2 królestwa")
	restyle_kingdoms_option.add_item("3 królestwa")
	restyle_kingdoms_option.add_item("4 królestwa")
	restyle_kingdoms_option.selected = 2
	vbox.add_child(restyle_kingdoms_option)

	restyle_density_option = OptionButton.new()
	restyle_density_option.custom_minimum_size = Vector2(0, 32)
	restyle_density_option.add_item("Zagęszczone (dużo małych grupek)")
	restyle_density_option.add_item("Kolonizacja (małe grupki, dużo pustych)")
	restyle_density_option.selected = 0
	vbox.add_child(restyle_density_option)

	restyle_btn = Button.new()
	restyle_btn.text = "🔄 Zastosuj styl na mapie"
	restyle_btn.custom_minimum_size = Vector2(0, 34)
	restyle_btn.pressed.connect(_on_restyle)
	vbox.add_child(restyle_btn)

func _add_label(parent: VBoxContainer, txt: String, size: int):
	var lbl = Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", size)
	parent.add_child(lbl)

func _add_sep(parent: VBoxContainer):
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 4)
	parent.add_child(sep)

# ============================================================

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F9:
			visible = not visible

# ============================================================
# Główna logika
# ============================================================

func _on_clear_map():
	if not hex_grid:
		return
	hex_grid.clear_grid()
	hex_grid.team_gold  = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	hex_grid.castle_gold = {}
	_set_info("🗑️ Mapa wyczyszczona.", Color.YELLOW)

func _on_generate():
	if not hex_grid:
		_set_info("❌ Brak hex_grid!", Color.RED)
		return

	var rng_s = RandomNumberGenerator.new()
	rng_s.randomize()
	var size_idx = size_option.selected
	var ranges = SIZE_RANGES[size_idx]
	var map_size = Vector2i(
		rng_s.randi_range(ranges["w_min"], ranges["w_max"]),
		rng_s.randi_range(ranges["h_min"], ranges["h_max"])
	)
	var num_kingdoms = kingdoms_option.selected + 2
	var is_blank  = blank_map_checkbox.button_pressed
	var colonize  = neutral_checkbox.button_pressed

	_generate_map(map_size, num_kingdoms, is_blank, colonize)


func _generate_map(map_size: Vector2i, num_kingdoms: int, blank_mode: bool, colonize: bool):
	hex_grid.clear_grid()
	hex_grid.team_gold  = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	hex_grid.castle_gold = {}

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	var W = map_size.x
	var H = map_size.y

	# 1. Kształt mapy
	var hex_set = _generate_island_shape(rng, W, H)

	# 2. Postaw hexy
	for coords in hex_set:
		hex_grid.add_hex_at(coords)
	await hex_grid.get_tree().process_frame

	if blank_mode:
		_place_blank_map_kingdoms(rng, hex_set, num_kingdoms)
	else:
		# 3. Wybierz pozycje zamków (spread) – bez stawiania
		var castle_positions = _pick_castle_positions_spread(rng, hex_set, num_kingdoms)

		# 4. Dla każdego zamku: postaw zamek + farmer + dokładnie N pól wokół (max 5 łącznie)
		#    Liczba pól jest taka sama dla WSZYSTKICH zamków wszystkich królestw
		var fields_per_castle = rng.randi_range(3, 5)  # łącznie z zamkiem i farmerem
		_place_castles_with_exact_fields(rng, castle_positions, num_kingdoms, fields_per_castle)

		# 5. Dodatkowe losowe grupki (archipelag) – izolowane od zamków
		#    Każde królestwo dostaje tyle samo dodatkowych pól
		if not colonize:
			_paint_extra_patches(rng, hex_set, num_kingdoms, castle_positions, false)
		else:
			_paint_extra_patches(rng, hex_set, num_kingdoms, castle_positions, true)

	# 6. Przelicz
	for t in [1, 2, 3, 4]:
		hex_grid.recalculate_kingdoms(t)
	hex_grid._ensure_unique_kingdom_ids()
	for t in [1, 2, 3, 4]:
		hex_grid.recalculate_kingdoms(t)

	hex_grid.team_gold  = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	hex_grid.castle_gold = {}
	for coords in hex_grid.castle_map:
		var t = hex_grid.castle_map[coords].team
		if t > 0 and t <= 4:
			hex_grid.team_gold[t] = hex_grid.team_gold.get(t, 0) + 8
	for t in [1, 2, 3, 4]:
		hex_grid._redistribute_castle_gold(t)

	await hex_grid.get_tree().process_frame
	hex_grid._update_castle_gold_labels()
	hex_grid.update_ui()


# ============================================================
# Kształt mapy
# ============================================================

func _generate_island_shape(rng: RandomNumberGenerator, W: int, H: int) -> Array:
	var occupied = {}
	var num_blobs = rng.randi_range(3, 6)
	var margin = 2

	var blob_centers = []
	for _i in range(num_blobs):
		blob_centers.append(Vector2i(
			rng.randi_range(margin, max(margin, W - margin - 1)),
			rng.randi_range(margin, max(margin, H - margin - 1))
		))

	var blob_radii = []
	for _i in range(num_blobs):
		blob_radii.append(rng.randf_range(min(W, H) * 0.22, min(W, H) * 0.48))

	for q in range(W):
		for r in range(H):
			var coords = Vector2i(q, r)
			for i in range(blob_centers.size()):
				if _dist(coords, blob_centers[i]) <= blob_radii[i]:
					occupied[coords] = true
					break

	# Wygładź krawędzie
	var keys_list = occupied.keys()
	keys_list.shuffle()
	var smooth_remove = int(occupied.size() * rng.randf_range(0.04, 0.10))
	var removed = 0
	for k in keys_list:
		if removed >= smooth_remove:
			break
		var missing = 0
		for nb in _neighbors(k):
			if not occupied.has(nb):
				missing += 1
		if missing >= 2:
			occupied.erase(k)
			removed += 1

	# Dziury wewnętrzne
	var inner = []
	for k in occupied.keys():
		var all_in = true
		for nb in _neighbors(k):
			if not occupied.has(nb):
				all_in = false
				break
		if all_in:
			inner.append(k)
	inner.shuffle()
	var hole_count = int(occupied.size() * rng.randf_range(0.08, 0.18))
	for i in range(min(hole_count, inner.size())):
		occupied.erase(inner[i])

	return _keep_largest(occupied.keys())

# ============================================================
# Wybór pozycji zamków – spread
# ============================================================

func _pick_castle_positions_spread(rng: RandomNumberGenerator, hex_set: Array, num_kingdoms: int) -> Dictionary:
	"""
	Zwraca Dictionary: team -> Array[Vector2i] pozycji zamków.
	Zamki każdego teamu są rozrzucone po całej mapie.
	Zamki różnych teamów też trzymają dystans od siebie.
	"""
	var total_hexes = hex_set.size()
	var castles_per_kingdom = 1
	if total_hexes > 250:
		castles_per_kingdom = 3
	elif total_hexes > 100:
		castles_per_kingdom = 2

	# Wszystkie już wybrane pozycje zamków (wszystkie teamy)
	var all_castle_pos: Array = []
	var result: Dictionary = {}

	for team in range(1, num_kingdoms + 1):
		result[team] = []

	# Losuj pozycje dla każdego teamu, naprzemiennie (żeby były wymieszane geograficznie)
	for castle_idx in range(castles_per_kingdom):
		for team in range(1, num_kingdoms + 1):
			var candidates = hex_set.duplicate()
			candidates.shuffle()
			# Weź próbkę max 120 kandydatów
			var sample = candidates.slice(0, min(120, candidates.size()))

			var best_pos = Vector2i(-9999, -9999)
			var best_score = -1.0

			for candidate in sample:
				# Musi być wolny hex
				if not _hex_free(candidate):
					continue
				# Musi mieć min 1 sąsiada na mapie (żeby farmer mógł stanąć)
				var has_free_nb = false
				for nb in _neighbors(candidate):
					if hex_grid.hex_map.has(nb):
						has_free_nb = true
						break
				if not has_free_nb:
					continue

				# Score = min dystans do WSZYSTKICH już wybranych zamków
				var min_d = INF
				for pos in all_castle_pos:
					var d = _dist(candidate, pos)
					if d < min_d:
						min_d = d

				# Bonus jeśli to pierwszy zamek tego teamu – nie ma ograniczeń
				if all_castle_pos.is_empty():
					min_d = 999.0

				if min_d > best_score:
					best_score = min_d
					best_pos = candidate

			if best_pos != Vector2i(-9999, -9999):
				result[team].append(best_pos)
				all_castle_pos.append(best_pos)

	return result

# ============================================================
# Stawianie zamków z dokładną liczbą pól
# ============================================================

func _place_castles_with_exact_fields(rng: RandomNumberGenerator, castle_positions: Dictionary,
									   num_kingdoms: int, fields_per_castle: int):
	"""
	Dla każdego zamku:
	- Postaw zamek (pole 1)
	- Postaw farmera na bezpośrednim sąsiedzie (pole 2)
	- Dodaj (fields_per_castle - 2) dodatkowych sąsiednich pól (pokolorowanych, pustych)
	Łącznie zawsze dokładnie fields_per_castle pól.
	Taka sama liczba dla każdego zamku każdego królestwa = pełna równość.
	"""
	for team in range(1, num_kingdoms + 1):
		var positions = castle_positions.get(team, [])
		for castle_pos in positions:
			if not hex_grid.hex_map.has(castle_pos):
				continue

			# Postaw zamek i oznacz terytorium
			hex_grid.territory_map[castle_pos] = team
			hex_grid.update_hex_color(castle_pos)
			hex_grid.place_castle_at(castle_pos, team)

			# Zbierz sąsiednie hexy na mapie (losowa kolejność)
			var nbs = _neighbors(castle_pos)
			nbs.shuffle()
			var free_nbs = []
			for nb in nbs:
				if hex_grid.hex_map.has(nb):
					free_nbs.append(nb)

			if free_nbs.is_empty():
				continue

			# Pole 2: farmer bezpośrednio obok zamku
			var farmer_pos = free_nbs[0]
			hex_grid.territory_map[farmer_pos] = team
			hex_grid.update_hex_color(farmer_pos)
			hex_grid.place_farmer_at(farmer_pos, team)

			# Pola 3 do fields_per_castle: kolejne sąsiednie hexy (puste, pokolorowane)
			var extra_needed = fields_per_castle - 2  # ile dodatkowych pól
			var extra_added = 0
			for i in range(1, free_nbs.size()):
				if extra_added >= extra_needed:
					break
				var nb = free_nbs[i]
				# Nie stawiaj na już zajętym polu
				if hex_grid.territory_map.get(nb, 0) != 0:
					continue
				var nb_hx = hex_grid.get_hex_at(nb)
				if not nb_hx or nb_hx.occupied_object != null:
					continue
				hex_grid.territory_map[nb] = team
				hex_grid.update_hex_color(nb)
				extra_added += 1

# ============================================================
# Dodatkowe grupki archipelagowego – ODDZIELONE od zamków
# ============================================================

func _paint_extra_patches(rng: RandomNumberGenerator, hex_set: Array, num_kingdoms: int,
						   castle_positions: Dictionary, colonize: bool):
	"""
	Sieje dodatkowe małe grupki (archipelag) z dala od zamków.
	Każda grupka ma 3-15 pól i jest oddzielona buforem od innych grupek tego samego koloru.
	Każde królestwo dostaje tyle samo dodatkowych pól (równość).
	"""
	var set_dict = {}
	for h in hex_set:
		set_dict[h] = true

	# Ile pól już zajętych (zamki + ich pola startowe)
	var already_colored = hex_grid.territory_map.size()
	var total = hex_set.size()

	# Ile dodatkowych pól łącznie
	var extra_total: int
	if colonize:
		extra_total = int(total * rng.randf_range(0.10, 0.22))
	else:
		extra_total = int(total * rng.randf_range(0.35, 0.55))

	# Podziel równo między królestwa
	var per_kingdom = int(extra_total / num_kingdoms)
	var remaining = {}
	for t in range(1, num_kingdoms + 1):
		remaining[t] = per_kingdom

	# assigned = kopia territory_map (żeby wiedzieć co już zajęte)
	# Używamy hex_grid.territory_map bezpośrednio

	# Pula wolnych hexów (nie zajętych)
	var free_pool = []
	for h in hex_set:
		if hex_grid.territory_map.get(h, 0) == 0:
			free_pool.append(h)
	free_pool.shuffle()
	var pool_idx = 0

	var any_progress = true
	while any_progress:
		any_progress = false
		for team in range(1, num_kingdoms + 1):
			if remaining[team] <= 0:
				continue

			# Znajdź zarodek: wolny hex, który NIE sąsiaduje z polem tego teamu
			var seed = Vector2i(-9999, -9999)
			var scanned = 0
			while pool_idx < free_pool.size():
				var candidate = free_pool[pool_idx]
				pool_idx += 1
				scanned += 1
				if hex_grid.territory_map.get(candidate, 0) != 0:
					continue
				# Nie może sąsiadować z tym samym teamem (izolacja grupek)
				var touches_team = false
				for nb in _neighbors(candidate):
					if hex_grid.territory_map.get(nb, 0) == team:
						touches_team = true
						break
				if touches_team:
					continue
				seed = candidate
				break

			if seed == Vector2i(-9999, -9999):
				# Pool się skończył – przetasuj i spróbuj jeszcze raz
				if pool_idx >= free_pool.size() and scanned > 0:
					free_pool.shuffle()
					pool_idx = 0
				continue

			# Rozmiar grupki: losowy, max to co zostało budżetu
			var patch_size = _pick_patch_size(rng)
			patch_size = min(patch_size, remaining[team])

			# Rośnij grupkę
			var patch = _grow_isolated_patch(rng, seed, patch_size, set_dict, team)

			for h in patch:
				hex_grid.territory_map[h] = team
				hex_grid.update_hex_color(h)
				remaining[team] -= 1

			if not patch.is_empty():
				any_progress = true

		# Reset pool jeśli się skończył a są jeszcze potrzeby
		if pool_idx >= free_pool.size():
			var any_remaining = false
			for t in range(1, num_kingdoms + 1):
				if remaining[t] > 0:
					any_remaining = true
					break
			if any_remaining:
				free_pool.shuffle()
				pool_idx = 0
			else:
				break


func _grow_isolated_patch(rng: RandomNumberGenerator, seed: Vector2i, max_size: int,
						   set_dict: Dictionary, team: int) -> Array:
	"""
	Rośnie grupkę. Żaden hex w grupce nie może sąsiadować
	z już istniejącym polem TEGO teamu (izolacja od innych grupek).
	"""
	var patch = [seed]
	var frontier = [seed]

	while not frontier.is_empty() and patch.size() < max_size:
		var idx = rng.randi_range(0, frontier.size() - 1)
		var cur = frontier[idx]
		frontier.remove_at(idx)

		var nbs = _neighbors(cur)
		nbs.shuffle()
		for nb in nbs:
			if patch.size() >= max_size:
				break
			if not set_dict.has(nb):
				continue
			if hex_grid.territory_map.get(nb, 0) != 0:
				continue
			# Nie dołączaj jeśli sąsiaduje z istniejącym polem tego teamu
			# (sprawdzamy territory_map, nie patch – patch to nowo tworzone pola)
			var touches_existing = false
			for nb2 in _neighbors(nb):
				if nb2 in patch:
					continue  # sąsiad z tej samej grupki – OK
				if hex_grid.territory_map.get(nb2, 0) == team:
					touches_existing = true
					break
			if touches_existing:
				continue
			patch.append(nb)
			frontier.append(nb)

	return patch


func _pick_patch_size(rng: RandomNumberGenerator) -> int:
	var roll = rng.randf()
	if roll < 0.30:
		return rng.randi_range(3, 4)
	elif roll < 0.55:
		return rng.randi_range(4, 6)
	elif roll < 0.73:
		return rng.randi_range(5, 8)
	elif roll < 0.87:
		return rng.randi_range(7, 11)
	else:
		return rng.randi_range(10, 15)

# ============================================================
# Tryb "czysta mapa"
# ============================================================

func _place_blank_map_kingdoms(rng: RandomNumberGenerator, hex_set: Array, num_kingdoms: int):
	var set_dict = {}
	for h in hex_set:
		set_dict[h] = true

	var border_hexes = []
	for h in hex_set:
		for nb in _neighbors(h):
			if not set_dict.has(nb):
				border_hexes.append(h)
				break

	if border_hexes.is_empty():
		border_hexes = hex_set.duplicate()

	border_hexes.shuffle()
	var sector_size = int(border_hexes.size() / num_kingdoms)

	for k in range(num_kingdoms):
		var team = k + 1
		var start = k * sector_size
		var end_idx = min(start + sector_size, border_hexes.size())
		var sector = border_hexes.slice(start, end_idx)
		sector.shuffle()

		var placed = false
		for castle_coords in sector:
			if not _hex_free(castle_coords):
				continue

			var free_nbs = []
			for nb in _neighbors(castle_coords):
				if hex_grid.hex_map.has(nb) and not hex_grid.castle_map.has(nb):
					var h2 = hex_grid.get_hex_at(nb)
					if h2 and h2.occupied_object == null:
						free_nbs.append(nb)

			if free_nbs.is_empty():
				continue

			hex_grid.territory_map[castle_coords] = team
			hex_grid.update_hex_color(castle_coords)
			hex_grid.place_castle_at(castle_coords, team)

			free_nbs.shuffle()
			hex_grid.territory_map[free_nbs[0]] = team
			hex_grid.update_hex_color(free_nbs[0])
			hex_grid.place_farmer_at(free_nbs[0], team)

			if free_nbs.size() > 1:
				hex_grid.territory_map[free_nbs[1]] = team
				hex_grid.update_hex_color(free_nbs[1])

			placed = true
			break

		if not placed:
			for h in hex_set:
				if not _hex_free(h):
					continue
				hex_grid.territory_map[h] = team
				hex_grid.update_hex_color(h)
				hex_grid.place_castle_at(h, team)
				for nb in _neighbors(h):
					if hex_grid.hex_map.has(nb) and not hex_grid.castle_map.has(nb):
						var h2 = hex_grid.get_hex_at(nb)
						if h2 and h2.occupied_object == null:
							hex_grid.territory_map[nb] = team
							hex_grid.update_hex_color(nb)
							hex_grid.place_farmer_at(nb, team)
							break
				break

# ============================================================
# Restyle
# ============================================================

func _on_restyle():
	if not hex_grid or hex_grid.hex_map.is_empty():
		_set_info("❌ Brak mapy do przetworzenia.", Color.RED)
		return

	var num_kingdoms = restyle_kingdoms_option.selected + 2
	var colonize = (restyle_density_option.selected == 1)

	for k in hex_grid.farmer_map.keys():
		hex_grid.remove_farmer_at(k)
	for k in hex_grid.castle_map.keys():
		hex_grid.remove_castle_at(k)
	hex_grid.territory_map.clear()
	for coords in hex_grid.hex_map:
		hex_grid.update_hex_color(coords)

	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var hex_list = hex_grid.hex_map.keys()

	var castle_positions = _pick_castle_positions_spread(rng, hex_list, num_kingdoms)
	var fields_per_castle = rng.randi_range(3, 5)
	_place_castles_with_exact_fields(rng, castle_positions, num_kingdoms, fields_per_castle)
	_paint_extra_patches(rng, hex_list, num_kingdoms, castle_positions, colonize)

	for t in [1, 2, 3, 4]:
		hex_grid.recalculate_kingdoms(t)
	hex_grid._ensure_unique_kingdom_ids()

	hex_grid.team_gold  = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	hex_grid.castle_gold = {}
	for coords in hex_grid.castle_map:
		var t = hex_grid.castle_map[coords].team
		if t > 0 and t <= 4:
			hex_grid.team_gold[t] = hex_grid.team_gold.get(t, 0) + 8
	for t in [1, 2, 3, 4]:
		hex_grid._redistribute_castle_gold(t)

	await hex_grid.get_tree().process_frame
	hex_grid._update_castle_gold_labels()
	hex_grid.update_ui()

	_set_info("✅ Przestylistowano (%d królestw, %s, %d pól/zamek)." % [
		num_kingdoms, "zagęszczone" if not colonize else "kolonizacja", fields_per_castle
	], Color.GREEN)

# ============================================================
# Helpers
# ============================================================

func _hex_free(coords: Vector2i) -> bool:
	if not hex_grid.hex_map.has(coords):
		return false
	if hex_grid.castle_map.has(coords):
		return false
	var hx = hex_grid.get_hex_at(coords)
	return hx != null and hx.occupied_object == null

func _dist(a: Vector2i, b: Vector2i) -> float:
	return sqrt(float((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)))

func _neighbors(coords: Vector2i) -> Array:
	var q = coords.x
	var dirs: Array
	if q % 2 == 0:
		dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,-1), Vector2i(0,1), Vector2i(1,-1), Vector2i(-1,-1)]
	else:
		dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,-1), Vector2i(0,1), Vector2i(1,1), Vector2i(-1,1)]
	var result = []
	for d in dirs:
		result.append(coords + d)
	return result

func _keep_largest(hex_list: Array) -> Array:
	if hex_list.is_empty():
		return hex_list
	var set_dict = {}
	for h in hex_list:
		set_dict[h] = true
	var visited = {}
	var best: Array = []
	for start in hex_list:
		if visited.has(start):
			continue
		var comp: Array = []
		var queue = [start]
		visited[start] = true
		while not queue.is_empty():
			var cur = queue.pop_front()
			comp.append(cur)
			for nb in _neighbors(cur):
				if set_dict.has(nb) and not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
		if comp.size() > best.size():
			best = comp
	return best

func _set_info(text: String, color: Color):
	info_label.text = text
	info_label.add_theme_color_override("font_color", color)

func setup_for_hex_grid(grid: HexGrid):
	hex_grid = grid
