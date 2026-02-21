extends Area2D
class_name Hex

@export var grid_position: Vector2i = Vector2i.ZERO
@export var walkable: bool = true

@onready var sprite = $Sprite

var occupied_object = null
var current_color: Color = Color("#2b2b2b")
var is_highlighted: bool = false
var original_scale: Vector2 = Vector2.ONE

# Kingdom label - pokazuje do którego królestwa należy to pole
var kingdom_label: Label = null

func _ready():
	if not sprite:
		push_error("Brak Sprite2D w hex.tscn!")
		return
	
	original_scale = sprite.scale
	sprite.modulate = current_color
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# KRYTYCZNE: Ustaw input_pickable, żeby hex mógł przepuszczać eventy
	input_pickable = true

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var parent = get_parent()
			
			# W trybie gry - pozwól knightowi atakować zamek i jednostki
			var selected_is_valid = parent.selected_unit != null and is_instance_valid(parent.selected_unit)
			if parent.game_mode and selected_is_valid and parent.selected_unit is Knight:
				if occupied_object is Castle or occupied_object is Farmer or occupied_object is Knight:
					parent.on_hex_clicked(self)
					return
			# Jeśli na hexie jest jednostka (NIE zamek), nie przechwytuj eventu
			if occupied_object != null and not occupied_object is Castle:
				return
			
			parent.on_hex_clicked(self)

func _on_mouse_entered():
	if sprite:
		# Jeśli hex ma zaznaczoną jednostkę - utrzymuj stan selected
		if has_meta("is_unit_selected") and get_meta("is_unit_selected"):
			return
		
		# NOWE: Jeśli hex jest highlighted (zielony) - tylko zmień skalę, NIE kolor
		if is_highlighted:
			animate_scale(original_scale * 0.85, 0.1)
			return  # <-- DODAJ RETURN tutaj!
		
		# Normalny hover dla nie-highlighted hexów
		if not occupied_object:
			animate_scale(original_scale * 0.9, 0.1)
			var hover_color = current_color.lightened(0.2)
			sprite.modulate = hover_color

func _on_mouse_exited():
	if not sprite:
		return
	
	# Nie resetuj jeśli hex ma zaznaczoną jednostkę
	if has_meta("is_unit_selected") and get_meta("is_unit_selected"):
		return
	
	# NOWE: Nie resetuj jeśli hex jest highlighted
	if is_highlighted:
		animate_scale(original_scale * 0.85, 0.1)  # Przywróć rozmiar highlighted
		return  # <-- NIE resetuj koloru!
	
	# Normalny reset
	animate_scale(original_scale, 0.1)
	sprite.modulate = current_color

func animate_scale(target_scale: Vector2, duration: float):
	"""Animuje skalę sprite'a"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sprite, "scale", target_scale, duration)

func animate_capture(new_color: Color):
	"""Animacja przejęcia pola — hex ugina się pod ciężarem jednostki i wraca"""
	# Zabij każdy trwający tween na sprite żeby nie było konfliktów
	if sprite.has_meta("capture_tween"):
		var old = sprite.get_meta("capture_tween")
		if is_instance_valid(old) and old.is_valid():
			old.kill()
	
	# Kolor zmienia się NATYCHMIAST (synchronicznie) — tak żeby current_color
	# był poprawny zanim pulse_available_units go odczyta
	set_color(new_color)
	
	# Skalę ustawiam od razu na "uderzenie" (bez animowania w dół — to ma być snap)
	sprite.scale = original_scale * Vector2(1.12, 0.78)
	
	# Jeden tween animuje powrót: odbicie w górę → osadzenie
	var tween = create_tween()
	sprite.set_meta("capture_tween", tween)
	
	# ODBICIE — sprężyna wypcha hex w górę z overshotem
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(sprite, "scale", original_scale * Vector2(0.95, 1.06), 0.12)
	
	# OSADZENIE — drobne drganie i powrót do normy
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sprite, "scale", original_scale, 0.1)

func set_color(color: Color):
	"""Ustawia kolor hexa"""
	if not sprite:
		return
	
	current_color = color
	if not is_highlighted:
		sprite.modulate = color

func reset_color():
	"""Przywraca domyślny ciemny kolor"""
	set_color(Color("#2b2b2b"))

func highlight(color: Color = Color.ORANGE):
	"""Podświetla hex (np. przy wyborze dostępnych pól)"""
	if not sprite:
		return
	
	is_highlighted = true
	sprite.modulate = color
	
	animate_scale(original_scale * 0.85, 0.2)
	
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(sprite, "modulate:a", 0.7, 0.5)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.5)

func unhighlight():
	"""Usuwa podświetlenie"""
	if not sprite:
		return
	
	is_highlighted = false
	var tweens = get_tree().get_processed_tweens()
	for tween in tweens:
		if tween.is_valid():
			tween.kill()
	
	sprite.modulate = current_color
	sprite.scale = original_scale

func place_object(object_node):
	"""Umieszcza obiekt (np. zamek, rycerz) na hexie"""
	if occupied_object:
		return false
	
	occupied_object = object_node
	object_node.position = position
	return true

func remove_object():
	"""Usuwa obiekt z hexa"""
	var obj = occupied_object
	occupied_object = null
	return obj

func has_knight() -> bool:
	"""Sprawdza czy na hexie jest rycerz"""
	return occupied_object != null and occupied_object is Knight

func get_knight() -> Knight:
	"""Zwraca rycerza z hexa (lub null)"""
	if has_knight():
		return occupied_object as Knight
	return null

func has_castle() -> bool:
	"""Sprawdza czy na hexie jest zamek"""
	return occupied_object != null and occupied_object is Castle
	
func on_unit_hover_start():
	"""Wywołane gdy kursor najedzie na jednostkę nad hexem"""
	if not sprite:
		return
	
	# NOWE: Jeśli hex jest highlighted (zielony) - tylko zmień skalę, NIE kolor
	if is_highlighted:
		animate_scale(original_scale * 0.9, 0.1)
		return  # <-- DODAJ RETURN tutaj!
	
	# Normalny hover - pomniejsz hex
	animate_scale(original_scale * 0.9, 0.1)
	
	# Rozjaśnij kolor (tylko dla nie-highlighted)
	var hover_color = current_color.lightened(0.2)
	sprite.modulate = hover_color

func on_unit_hover_end():
	"""Wywołane gdy kursor opuści jednostkę"""
	if not sprite:
		return
	
	# Nie resetuj jeśli hex jest zaznaczony
	if has_meta("is_unit_selected") and get_meta("is_unit_selected"):
		return
	
	# NOWE: Jeśli hex jest podświetlony - tylko przywróć rozmiar highlighted
	if is_highlighted:
		animate_scale(original_scale * 0.85, 0.1)
		return  # <-- NIE resetuj koloru!
	
	# Przywróć normalny rozmiar i kolor
	animate_scale(original_scale, 0.1)
	sprite.modulate = current_color
	
func set_selected_state(selected: bool):
	"""Ustawia hex w stan 'zaznaczony' - pomniejszony i rozjaśniony"""
	if not sprite:
		return
	
	if selected:
		# ZMIANA: Zapisz CURRENT_COLOR zamiast sprite.modulate
		set_meta("original_color_selected", current_color)
		
		# Pomniejsz i rozjaśnij (jak w hover)
		animate_scale(original_scale * 0.9, 0.1)
		var hover_color = current_color.lightened(0.2)
		sprite.modulate = hover_color
		
		# Zaznacz że hex jest w stanie selected
		set_meta("is_unit_selected", true)
	else:
		# Przywróć normalny stan
		remove_meta("is_unit_selected")
		
		# DODAJ: Przywróć current_color
		sprite.modulate = current_color
		animate_scale(original_scale, 0.1)

# ============== KINGDOM LABEL ==============

func set_kingdom_label(kingdom_id: int, show: bool):
	"""Ustawia etykietę królestwa na hexie (dynamiczna - może się zmieniać)"""
	if kingdom_id <= 0:
		# Brak królestwa - ukryj etykietę
		if kingdom_label:
			kingdom_label.visible = false
		return
	
	if not kingdom_label:
		kingdom_label = Label.new()
		kingdom_label.z_index = 25
		add_child(kingdom_label)
	
	kingdom_label.text = str(kingdom_id)
	kingdom_label.add_theme_font_size_override("font_size", 14)
	kingdom_label.add_theme_color_override("font_color", Color.WHITE)
	kingdom_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	kingdom_label.add_theme_constant_override("shadow_offset_x", 1)
	kingdom_label.add_theme_constant_override("shadow_offset_y", 1)
	kingdom_label.add_theme_constant_override("shadow_as_outline", 1)
	kingdom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kingdom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kingdom_label.size = Vector2(20, 20)
	# Dół hexa, ale żeby nie zasłaniać jednostki - lekko niżej centrum
	kingdom_label.position = Vector2(-10, 22)
	kingdom_label.visible = show

func update_kingdom_label_visibility(show: bool):
	"""Aktualizuje widoczność etykiety"""
	if kingdom_label:
		kingdom_label.visible = show and kingdom_label.text != "" and kingdom_label.text != "0"

func clear_kingdom_label():
	"""Usuwa etykietę królestwa"""
	if kingdom_label:
		kingdom_label.visible = false
		kingdom_label.text = ""
