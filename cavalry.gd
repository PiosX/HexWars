extends Node2D
class_name Cavalry

@export var team: int = 1
@export var hex_position: Vector2i = Vector2i.ZERO

var sprite = null
var area = null
var is_selected: bool = false

func _ready():
	sprite = find_child_of_type(Sprite2D)
	
	if not sprite:
		push_error("Brak Sprite2D w cavalry.tscn!")
		return
	
	# Największy rozmiar (większy niż knight)
	var base_scale = 1.65
	sprite.scale = Vector2(base_scale, base_scale)
	
	area = find_child_of_type(Area2D)
	if not area:
		_create_area2d()
	
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
	shape.radius = 22
	collision.shape = shape
	area.add_child(collision)

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var parent = get_parent()
		
		if not (parent is HexGrid):
			return
		
		# W trybie gry - obsługa ataku
		if parent.game_mode:
			if parent.selected_unit != null and is_instance_valid(parent.selected_unit):
				# Jeśli selected unit to INNA jednostka i ten cavalry jest wrogi
				if parent.selected_unit != self and parent.selected_unit.team != team:
					# Wrogi unit atakuje tego cavalry
					print("CAVALRY: Wywołuję atak na mnie przez ", parent.selected_unit)
					var hex = parent.get_hex_at(hex_position)
					if hex:
						parent.on_hex_clicked(hex)
					return  # ← KRYTYCZNE: Zatrzymaj tu!
		
		# W przeciwnym razie - zaznacz tego cavalry
		print("CAVALRY: Zaznaczam siebie")
		if parent.has_method("on_cavalry_clicked"):
			parent.on_cavalry_clicked(self)
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
	if sprite:
		sprite.position = Vector2.ZERO
	
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
