extends Node2D

# --- Odwołania do TileMapLayer i zamków ---
@onready var tilemap = $TileMap         # Twój TileMapLayer
@onready var player_castle = tilemap.get_node("Castle1")
@onready var enemy_castle = tilemap.get_node("Castle2")

# --- Funkcja ustawiająca zamki na wybranych kafelkach ---
func place_castles():
	var player_cell = Vector2i(-1, 2)    # współrzędne hex dla gracza
	var enemy_cell  = Vector2i(-2, -3)   # współrzędne hex dla wroga
	
	# TileMapLayer.map_to_local() automatycznie zwraca wyśrodkowaną pozycję
	player_castle.position = tilemap.map_to_local(player_cell)
	enemy_castle.position = tilemap.map_to_local(enemy_cell)

# --- READY ---
func _ready():
	place_castles()
