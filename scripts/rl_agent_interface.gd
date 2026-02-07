extends Node
class_name RLAgentInterface

## INTERFEJS AGENTA RL DLA GODOT_RL_AGENTS
## ==========================================
## Ten skrypt jest MOSTEM między Pythonem a Twoim środowiskiem gry

# ============================================================================
# EKSPORTOWANE PARAMETRY
# ============================================================================
@export var rl_environment: StrategyGameRLEnv  ## PRZECIĄGNIJ istniejący RLEnvironment node!
@export var hex_grid: HexGrid  ## Referencja do siatki hex (opcjonalne jeśli RLEnvironment już ma)
@export var ai_team: int = 1  ## Który team kontroluje AI (1-4)
@export var max_steps_per_episode: int = 300  ## Max kroków w epizodzie

# ============================================================================
# ZMIENNE WEWNĘTRZNE
# ============================================================================
var rl_env: StrategyGameRLEnv  ## Referencja do środowiska RL
var episode_count: int = 0
var total_reward: float = 0.0
var needs_reset: bool = false  ## DODANE - flaga informująca Sync node że trzeba zresetować

# Debug
var last_action_time: float = 0.0

# ============================================================================
# INICJALIZACJA
# ============================================================================
func _ready():
	# WAŻNE: Dodaj się do grupy AGENT żeby Sync node nas widział!
	add_to_group("AGENT")
	
	print("🤖 RL AGENT INTERFACE - INICJALIZACJA")
	
	# SPRAWDŹ CZY UŻYTKOWNIK PODŁĄCZYŁ ISTNIEJĄCY RLEnvironment
	if rl_environment:
		print("✅ Używam istniejącego RLEnvironment node")
		rl_env = rl_environment
		
		# Zaktualizuj parametry jeśli podano
		if hex_grid:
			rl_env.hex_grid = hex_grid
		if ai_team > 0:
			rl_env.ai_team = ai_team
		if max_steps_per_episode > 0:
			rl_env.episode_max_steps = max_steps_per_episode
	
	# JEŚLI NIE - STWÓRZ NOWY (fallback)
	else:
		print("⚠️  Nie podłączono RLEnvironment - tworzę nowy")
		
		if not hex_grid:
			push_error("❌ hex_grid nie jest ustawiony! Przeciągnij HexGrid node w inspektorze.")
			return
		
		# Stwórz środowisko RL
		rl_env = StrategyGameRLEnv.new()
		rl_env.hex_grid = hex_grid
		rl_env.ai_team = ai_team
		rl_env.episode_max_steps = max_steps_per_episode
		add_child(rl_env)
		print("✅ Nowe środowisko RL utworzone")
	
	print("   Team: %d" % rl_env.ai_team)
	print("   Max kroków: %d" % rl_env.episode_max_steps)
	
	# Czekaj na połączenie z Pythonem
	print("⏳ Czekam na połączenie z Pythonem...")
	print("   (Uruchom: python train.py --editor)")

# ============================================================================
# API WYMAGANE PRZEZ GODOT_RL_AGENTS SYNC NODE
# ============================================================================

func get_obs() -> Dictionary:
	"""
	Zwraca obserwacje dla agenta.
	Wywoływane przez Sync node w każdej klatce.
	
	MUSI zwrócić Dictionary z kluczem 'obs' zawierającym Array floatów
	"""
	var obs_dict = rl_env.get_obs()
	
	# Upewnij się że zwracamy w poprawnym formacie dla Sync
	if obs_dict.has("obs"):
		return obs_dict
	else:
		# Spłaszcz dictionary do array
		var obs_array = []
		for key in obs_dict.keys():
			var value = obs_dict[key]
			if typeof(value) == TYPE_ARRAY:
				obs_array.append_array(value)
			else:
				obs_array.append(float(value))
		
		return {"obs": obs_array}

func get_reward() -> float:
	"""
	Zwraca nagrodę za ostatnią akcję.
	Wywoływane przez Sync node po każdej akcji.
	"""
	var reward = rl_env.current_reward  # ZMIENIONE - używaj current_reward zamiast get_reward()
	total_reward += reward
	return reward

func zero_reward() -> void:
	"""
	Resetuje nagrodę (wywoływane przez Sync po pobraniu).
	"""
	# Sync już pobrał nagrodę, możemy zresetować licznik w środowisku
	if rl_env:
		rl_env.current_reward = 0.0

func get_action_space() -> Dictionary:
	"""
	Definiuje przestrzeń akcji dla agenta RL.
	Wywoływane raz na początku przez Sync node.
	
	Możliwe typy:
	- "discrete" - pojedyncza liczba całkowita
	- "multidiscrete" - array liczb całkowitych
	- "continuous" - array liczb zmiennoprzecinkowych
	"""
	return rl_env.get_action_space()

func get_obs_space() -> Dictionary:
	"""
	Definiuje przestrzeń obserwacji dla agenta RL.
	Wywoływane raz na początku przez Sync node.
	
	Format: {"obs": {"size": [rozmiar], "space": "box"}}
	"""
	# Pobierz przykładową obserwację żeby poznać rozmiar
	var sample_obs = rl_env.get_obs()
	var obs_array = []
	
	if sample_obs.has("obs"):
		obs_array = sample_obs["obs"]
	else:
		# Spłaszcz
		for key in sample_obs.keys():
			var value = sample_obs[key]
			if typeof(value) == TYPE_ARRAY:
				obs_array.append_array(value)
			else:
				obs_array.append(float(value))
	
	return {
		"obs": {
			"size": [obs_array.size()],
			"space": "box"
		}
	}

func set_action(action) -> void:
	"""
	Wykonuje akcję otrzymaną od Pythona.
	Wywoływane przez Sync node gdy Python wysyła akcję.
	
	action może być:
	- int (dla discrete)
	- Array[int] (dla multidiscrete)
	- Array[float] (dla continuous)
	"""
	# USUNIĘTE: current_step += 1  
	# Licznik kroków jest teraz TYLKO w rl_env!
	
	last_action_time = Time.get_ticks_msec() / 1000.0
	
	# Debug co 50 kroków
	if rl_env.current_step % 50 == 0 and rl_env.current_step > 0:
		print("   Krok %d | Nagroda: %.2f | Total: %.2f" % [rl_env.current_step, rl_env.current_reward, total_reward])
	
	# Przekaż akcję do środowiska
	rl_env.set_action(action)

func get_done() -> bool:
	"""
	Sprawdza czy epizod się skończył.
	Wywoływane przez Sync node co klatkę.
	"""
	# Używaj TYLKO flagi done ze środowiska
	var done = rl_env.done
	
	if done and rl_env.current_step > 0:
		print("\n🏁 KONIEC EPIZODU %d" % episode_count)
		print("   Kroków: %d" % rl_env.current_step)
		print("   Całkowita nagroda: %.2f" % total_reward)
		print("   Średnia nagroda: %.2f\n" % (total_reward / rl_env.current_step))
	
	return done

func set_done_false() -> void:
	"""
	Resetuje flagę done (wywoływane przez Sync po odczytaniu).
	"""
	if rl_env:
		rl_env.done = false

func set_heuristic(heuristic: String) -> void:
	"""
	Ustawia tryb kontroli: "model" (Python AI) lub "human" (ręczna kontrola).
	Wywoływane przez Sync node podczas inicjalizacji.
	"""
	print("🎮 Tryb kontroli: %s" % heuristic)
	# W naszym przypadku nie trzeba nic robić - zawsze Python kontroluje

func get_needs_reset() -> bool:
	"""
	Czy środowisko potrzebuje resetu?
	Wywoływane przez Sync node.
	"""
	return needs_reset or rl_env.needs_reset or get_done()

func reset() -> void:
	"""
	Resetuje środowisko na nowy epizod.
	Wywoływane przez Sync node gdy epizod się kończy.
	"""
	episode_count += 1
	
	print("\n🔄 RESET - Epizod %d" % episode_count)
	
	# Resetuj liczniki
	total_reward = 0.0
	needs_reset = false  # DODANE - resetuj flagę
	
	# Resetuj środowisko
	rl_env.reset()
	
	print("✅ Środowisko zresetowane\n")

# ============================================================================
# DEBUG & MONITORING
# ============================================================================

func _process(_delta):
	"""Monitoring stanu w czasie rzeczywistym"""
	# Można tu dodać wyświetlanie statystyk
	pass

func get_info() -> Dictionary:
	"""
	Opcjonalne - dodatkowe informacje dla Pythona.
	Nie wymagane przez godot_rl_agents, ale przydatne do debugowania.
	"""
	return {
		"episode": episode_count,
		"step": rl_env.current_step,
		"total_reward": total_reward,
		"ai_team": ai_team,
		"gold": hex_grid.team_gold.get(ai_team, 0) if hex_grid else 0,
	}

# ============================================================================
# POMOCNICZE FUNKCJE
# ============================================================================

func get_current_performance() -> Dictionary:
	"""Zwraca aktualne statystyki wydajności"""
	return {
		"episodes_completed": episode_count,
		"current_step": rl_env.current_step,
		"average_reward": total_reward / max(rl_env.current_step, 1),
		"fps": Engine.get_frames_per_second(),
	}
