extends Node2D
class_name Castle

@export var team: int = 1  # 1 = niebieski, 2 = czerwony
@export var hex_position: Vector2i = Vector2i.ZERO

var sprite = null
var area = null
var base_scale: Vector2
var hover_scale: Vector2

# Kingdom label (stały - pokazuje ID zamku, nigdy nie zmienia się poza reinicjalizacją)
var kingdom_label: Label = null

func _ready():
	# Znajdź Sprite2D (może mieć różne nazwy)
	sprite = find_child_of_type(Sprite2D)
	
	# Znajdź lub stwórz Area2D
	area = find_child_of_type(Area2D)
	if not area:
		_create_area2d()
		
	base_scale = sprite.scale
	hover_scale = base_scale * 0.85
	
	# Podłącz sygnały tylko jeśli area istnieje
	if area:
		if not area.input_event.is_connected(_on_input_event):
			area.input_event.connect(_on_input_event)
		if not area.mouse_entered.is_connected(_on_mouse_entered):
			area.mouse_entered.connect(_on_mouse_entered)
		if not area.mouse_exited.is_connected(_on_mouse_exited):
			area.mouse_exited.connect(_on_mouse_exited)

func find_child_of_type(type):
	"""Znajduje pierwsze dziecko danego typu"""
	for child in get_children():
		if is_instance_of(child, type):
			return child
	return null

func _create_area2d():
	"""Tworzy Area2D z collision shape"""
	area = Area2D.new()
	add_child(area)
	
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 30
	collision.shape = shape
	area.add_child(collision)
	
	print("Utworzono Area2D dla zamku na pozycji: ", hex_position)

func set_kingdom_label(kingdom_id: int, visible_labels: bool):
	"""Ustawia etykietę ID królestwa na zamku (stały - tylko dla zamków niebandyckich)"""
	if team <= 0:
		if kingdom_label:
			kingdom_label.visible = false
		return
	
	if kingdom_id <= 0:
		if kingdom_label:
			kingdom_label.visible = false
		return
	
	if not kingdom_label:
		kingdom_label = Label.new()
		kingdom_label.z_index = 30
		add_child(kingdom_label)
	
	kingdom_label.text = str(kingdom_id)
	kingdom_label.add_theme_font_size_override("font_size", 14)  # Taki sam jak hex
	kingdom_label.add_theme_color_override("font_color", Color.WHITE)
	kingdom_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	kingdom_label.add_theme_constant_override("shadow_offset_x", 1)
	kingdom_label.add_theme_constant_override("shadow_offset_y", 1)
	kingdom_label.add_theme_constant_override("shadow_as_outline", 1)
	kingdom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kingdom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kingdom_label.size = Vector2(20, 20)
	kingdom_label.position = Vector2(-10, 22)  # Taka sama pozycja jak na hexach
	kingdom_label.visible = visible_labels

func update_label_visibility(visible_labels: bool):
	"""Aktualizuje widoczność etykiety"""
	if kingdom_label:
		# Pokaż tylko jeśli ma sensowny tekst i team > 0
		kingdom_label.visible = visible_labels and team > 0 and kingdom_label.text != "" and kingdom_label.text != "0"

func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var parent = get_parent()
			
			# W trybie gry NIE przechwytuj eventu - pozwól knightowi kliknąć
			if parent is HexGrid and parent.game_mode:
				# USUŃ return - pozwól eventowi przejść dalej
				pass  # Event przejdzie przez zamek do hexa
			
			# W trybie edytora obsłuż kliknięcie
			elif parent.has_method("on_castle_clicked"):
				parent.on_castle_clicked(self)

func _on_mouse_entered():
	if sprite:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(sprite, "scale", hover_scale, 0.1)

	var parent = get_parent()
	if parent is HexGrid:
		var hex = parent.get_hex_at(hex_position)
		if hex and hex.has_method("on_unit_hover_start"):
			hex.on_unit_hover_start()

func _on_mouse_exited():
	if sprite:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(sprite, "scale", base_scale, 0.1)

	var parent = get_parent()
	if parent is HexGrid:
		var hex = parent.get_hex_at(hex_position)
		if hex and hex.has_method("on_unit_hover_end"):
			hex.on_unit_hover_end()
