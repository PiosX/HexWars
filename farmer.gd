extends Node2D
class_name Farmer

@export var team: int = 1
@export var hex_position: Vector2i = Vector2i.ZERO
var spawn_turn: int = -1  # NOWE: Tura w której jednostka się zrespila

var sprite = null
var area = null
var is_selected: bool = false

func _ready():
	sprite = find_child_of_type(Sprite2D)
	
	if not sprite:
		push_error("Brak Sprite2D w farmer.tscn!")
		return
	
	# Ustaw rozmiar mniejszy niż knight
	var base_scale = 1.0
	sprite.scale = Vector2(base_scale, base_scale)
	
	if team == -1:
		var bandit_tex = load("res://ui/bandit.png")
		if bandit_tex:
			sprite.texture = bandit_tex
	
	# Znajdź lub stwórz Area2D
	area = find_child_of_type(Area2D)
	if not area:
		_create_area2d()
	
	# Podłącz sygnały
	if area:
		if not area.input_event.is_connected(_on_input_event):
			area.input_event.connect(_on_input_event)
		if not area.mouse_entered.is_connected(_on_mouse_entered):
			area.mouse_entered.connect(_on_mouse_entered)
		if not area.mouse_exited.is_connected(_on_mouse_exited):
			area.mouse_exited.connect(_on_mouse_exited)

func find_child_of_type(type):
	for child in get_children():
		if is_instance_of(child, type):
			return child
	return null

func _create_area2d():
	area = Area2D.new()
	add_child(area)
	
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 18
	collision.shape = shape
	area.add_child(collision)

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var parent = get_parent()
		
		if not (parent is HexGrid):
			return
		
		if parent.game_mode:
			# BUY MODE
			if parent.buy_mode != "":
				var hex = parent.get_hex_at(hex_position)
				# Własna jednostka poza podświetlonymi → anuluj buy mode i zaznacz
				if team == parent.current_team and hex and hex not in parent.highlighted_hexes:
					if parent.has_method("on_farmer_clicked"):
						parent.on_farmer_clicked(self)
						get_viewport().set_input_as_handled()
					return
				# Inaczej → obsłuż jako klik w buy mode
				if hex:
					parent.on_hex_clicked(hex)
					get_viewport().set_input_as_handled()
				return
			
			# MERGE MODE: kliknięcie na własnego farmera w trybie łączenia
			if parent.merge_mode and team == parent.current_team:
				var hex = parent.get_hex_at(hex_position)
				if hex:
					parent.on_hex_clicked(hex)
					get_viewport().set_input_as_handled()
				return
			
			# ATAK: zaznaczona wroga jednostka atakuje tego farmera
			if parent.selected_unit != null and is_instance_valid(parent.selected_unit):
				if parent.selected_unit != self and parent.selected_unit.team != team:
					var hex = parent.get_hex_at(hex_position)
					if hex:
						parent.on_hex_clicked(hex)
					return
					
			if parent.selected_unit != null and is_instance_valid(parent.selected_unit):
				if parent.selected_unit != self and parent.selected_unit is Farmer and parent.selected_unit.team == team:
					parent.merge_farmers_to_spearman(parent.selected_unit.hex_position, hex_position)
					get_viewport().set_input_as_handled()
					return
		
		# Normalny przypadek: zaznacz tego farmera
		print("FARMER: Wywołuję on_farmer_clicked")
		if parent.has_method("on_farmer_clicked"):
			parent.on_farmer_clicked(self)
			get_viewport().set_input_as_handled()

func _on_mouse_entered():
	if DisplayServer.is_touchscreen_available():
		return
	animate_scale(Vector2(0.85, 0.85), 0.1)
	var parent = get_parent()
	if parent is HexGrid:
		var hex = parent.get_hex_at(hex_position)
		if hex and hex.has_method("on_unit_hover_start"):
			hex.on_unit_hover_start()

func _on_mouse_exited():
	if not is_selected:
		animate_scale(Vector2(1.0, 1.0), 0.1)
	var parent = get_parent()
	if parent is HexGrid:
		var hex = parent.get_hex_at(hex_position)
		if hex and hex.has_method("on_unit_hover_end"):
			hex.on_unit_hover_end()

func animate_scale(target_scale: Vector2, duration: float):
	if not sprite:
		return
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "scale", target_scale, duration)

func animate_slide_to(target_pos: Vector2, duration: float):
	"""Płynne przesunięcie do celu"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "position", target_pos, duration)

func set_selected(selected: bool):
	if not sprite:
		return
	
	is_selected = selected
	if selected:
		sprite.scale = Vector2(0.85, 0.85)
	else:
		sprite.scale = Vector2(1.0, 1.0)
