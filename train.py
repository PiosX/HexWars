"""
TRAIN.PY - Trening RL dla gry strategicznej hex
Używa godot_rl_agents + stable-baselines3 (PPO)

Obsługuje 2 agentów (Team 1 vs Team 2) trenujących się na sobie - POPRAWIONA WERSJA
"""

import argparse
import os
import time
from pathlib import Path
from typing import Optional

import gymnasium as gym
import numpy as np
from godot_rl.core.godot_env import GodotEnv
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback, EvalCallback
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import DummyVecEnv, VecNormalize


# ============================================================================
# MULTI-AGENT WRAPPER - POPRAWIONA WERSJA
# ============================================================================

class MultiAgentGodotWrapper(gym.Env):
    """
    Wrapper dla wielu agentów z godot_rl_agents.
    
    KLUCZOWA ZMIANA:
    - godot_rl oczekuje akcji jako PROSTE LISTY: [action0, action1, ...]
    - NIE jako zagnieżdżone listy: [[action0], [action1], ...]
    """
    
    def __init__(self, env):
        super().__init__()
        self.env = env
        
        # Pobierz liczę agentów z środowiska
        action_space_info = env.action_space
        
        # godot_rl_agents zwraca Tuple of spaces (jeden per agent)
        if isinstance(action_space_info, gym.spaces.Tuple):
            self.n_agents = len(action_space_info.spaces)
            self.action_space = action_space_info.spaces[0]
            print(f"✅ Wykryto {self.n_agents} agentów (Tuple space)")
        else:
            # Fallback: jeśli nie Tuple, zakładamy 1 agenta
            self.n_agents = 1
            self.action_space = action_space_info
            print(f"⚠️ Wykryto 1 agenta (non-Tuple space)")
        
        # Observation space
        obs_space_info = env.observation_space
        if isinstance(obs_space_info, gym.spaces.Dict):
            # Rozpakuj 'obs' z Dict
            self.observation_space = obs_space_info['obs']
            print(f"✅ Observation space (z Dict): {self.observation_space}")
        else:
            self.observation_space = obs_space_info
            print(f"✅ Observation space (direct): {self.observation_space}")
        
        print(f"✅ Action space: {self.action_space}")
        print(f"✅ MultiAgent Wrapper gotowy: {self.n_agents} agentów")
        
        # Bufor na akcje wszystkich agentów
        self.actions_buffer = []
        self.current_agent_idx = 0
        
        # Ostatnie dane ze środowiska
        self.last_obs_list = []
        self.last_reward_list = []
        self.last_terminated_list = []
        self.last_truncated_list = []
        self.last_info_list = []
    
    def reset(self, seed=None, options=None):
        """
        Reset środowiska. Zwraca obserwację pierwszego agenta.
        """
        if seed is not None:
            np.random.seed(seed)
        
        # Reset środowiska Godot
        result = self.env.reset()
        
        # godot_rl_agents zwraca (obs_list, info_list)
        if isinstance(result, tuple) and len(result) == 2:
            obs_list, info_list = result
            self.last_obs_list = obs_list
            self.last_info_list = info_list if info_list else [{}] * len(obs_list)
        else:
            # Starsza wersja lub pojedynczy agent
            self.last_obs_list = [result] if not isinstance(result, list) else result
            self.last_info_list = [{}] * len(self.last_obs_list)
        
        # Reset bufora akcji
        self.actions_buffer = []
        self.current_agent_idx = 0
        
        # Zwróć obserwację pierwszego agenta
        obs = self._extract_obs(self.last_obs_list[0])
        info = self.last_info_list[0]
        
        return obs, info
    
    def step(self, action):
        """
        Wykonaj akcję dla aktualnego agenta.
        
        Zbiera akcje od wszystkich agentów po kolei,
        a następnie wykonuje jeden step w środowisku Godot.
        """
        # Dodaj akcję do bufora
        self.actions_buffer.append(int(action))
        self.current_agent_idx += 1
        
        # Jeśli zebraliśmy akcje od WSZYSTKICH agentów
        if self.current_agent_idx >= self.n_agents:
            # ✅ KLUCZOWA POPRAWKA - format zależy od liczby agentów!
            if self.n_agents == 1:
                # Dla 1 agenta: godot_rl oczekuje [[akcja]]
                action_to_send = [[self.actions_buffer[0]]]
            else:
                # Dla wielu agentów: [akcja1, akcja2, ...]
                action_to_send = self.actions_buffer.copy()
            
            # Debug - pokaż format (tylko raz)
            if hasattr(self, '_first_step') and self._first_step:
                print(f"🔧 Wysyłam akcje: {action_to_send} (n_agents={self.n_agents}, typ: {type(action_to_send)})")
                self._first_step = False
            elif not hasattr(self, '_first_step'):
                self._first_step = True
                print(f"🔧 Wysyłam akcje: {action_to_send} (n_agents={self.n_agents}, typ: {type(action_to_send)})")
            
            # Wykonaj krok w środowisku Godot
            result = self.env.step(action_to_send)
            
            # Rozpakuj wynik
            if isinstance(result, tuple) and len(result) == 5:
                # Nowy format Gymnasium: (obs, reward, terminated, truncated, info)
                obs_list, reward_list, terminated_list, truncated_list, info_list = result
            elif isinstance(result, tuple) and len(result) == 4:
                # Stary format Gym: (obs, reward, done, info)
                obs_list, reward_list, done_list, info_list = result
                terminated_list = done_list
                truncated_list = [False] * len(done_list)
            else:
                raise ValueError(f"Nieoczekiwany format wyniku z env.step(): {result}")
            
            # Zapisz wyniki
            self.last_obs_list = obs_list
            self.last_reward_list = reward_list
            self.last_terminated_list = terminated_list
            self.last_truncated_list = truncated_list if truncated_list else [False] * len(obs_list)
            self.last_info_list = info_list if info_list else [{}] * len(obs_list)
            
            # Reset bufora
            self.actions_buffer = []
            self.current_agent_idx = 0
        
        # Zwróć dane dla PIERWSZEGO agenta (Team 1)
        # Stable-baselines3 uczy jeden model, który gra obiema stronami
        agent_idx = 0
        
        obs = self._extract_obs(self.last_obs_list[agent_idx])
        reward = float(self.last_reward_list[agent_idx])
        terminated = bool(self.last_terminated_list[agent_idx])
        truncated = bool(self.last_truncated_list[agent_idx])
        info = self.last_info_list[agent_idx]
        
        return obs, reward, terminated, truncated, info
    
    def _extract_obs(self, obs):
        """Wyciąga array z obserwacji (może być w dict z kluczem 'obs')"""
        if isinstance(obs, dict) and 'obs' in obs:
            obs_value = obs['obs']
        else:
            obs_value = obs
        
        # Konwertuj na numpy array
        if not isinstance(obs_value, np.ndarray):
            obs_value = np.array(obs_value, dtype=np.float32)
        
        return obs_value
    
    def render(self, mode='human'):
        """Renderowanie (opcjonalne)"""
        return self.env.render(mode=mode)
    
    def close(self):
        """Zamknięcie środowiska"""
        print("📚 Zamykam środowisko Godot")
        return self.env.close()


# ============================================================================
# FUNKCJE POMOCNICZE
# ============================================================================

def create_env(config: dict) -> gym.Env:
    """
    Tworzy środowisko Godot z wrapperem.
    """
    print(f"📦 Tworzę środowisko Godot...")
    
    # Ustawienia dla GodotEnv
    env_path = config.get("env_path", None)  # None = tryb edytora
    port = config.get("port", 10008)
    show_window = config.get("show_window", False)
    seed = config.get("seed", 0)
    timeout_wait = config.get("timeout_wait", 60)
    
    # Stwórz środowisko Godot
    godot_env = GodotEnv(
        env_path=env_path,
        port=port,
        show_window=show_window,
        seed=seed,
        timeout_wait=timeout_wait,
    )
    
    print(f"✅ GodotEnv utworzone (port: {port})")
    
    # Opakowujemy w wrapper dla wielu agentów
    wrapped_env = MultiAgentGodotWrapper(godot_env)
    print("✅ Środowisko gotowe!")
    
    return wrapped_env


def create_vec_env(config: dict) -> DummyVecEnv:
    """
    Tworzy vectorized environment (wymóg stable-baselines3).
    """
    print("🔧 Tworzę środowisko...")
    
    # Dla pojedynczego środowiska
    def make_env():
        env = create_env(config)
        env = Monitor(env)
        return env
    
    # Stable-baselines3 wymaga VecEnv
    vec_env = DummyVecEnv([make_env])
    
    # Opcjonalna normalizacja
    if config.get("normalize", False):
        vec_env = VecNormalize(
            vec_env,
            norm_obs=True,
            norm_reward=True,
            clip_obs=10.0,
            clip_reward=10.0,
        )
        print("✅ VecNormalize włączone")
    
    print("✅ Środowisko gotowe!")
    return vec_env


# ============================================================================
# TRENING
# ============================================================================

def train(config: dict):
    """
    Uruchamia trening modelu PPO.
    """
    # Banner
    print("=" * 70)
    print("🚀 START TRENINGU - MULTI-AGENT SELF-PLAY")
    print("=" * 70)
    print(f"📁 Projekt: {config['project_dir']}")
    print(f"🎮 Środowisk: {config['n_envs']}")
    print(f"⏱️  Kroków: {config['total_timesteps']:,}")
    print(f"💾 Zapis co: {config['save_freq']:,} kroków")
    print("=" * 70)
    
    # Tryb edytora?
    if config.get("editor_mode", False):
        print("\n⚠️  TRYB EDYTORA - Otwórz projekt w Godot i naciśnij F5!")
        print("    (Poczekaj na połączenie...)\n")
    
    # Utwórz środowisko
    env = create_vec_env(config)
    
    # Utwórz lub wczytaj model
    model_path = config.get("continue_from", None)
    
    if model_path and os.path.exists(model_path):
        print(f"📂 Wczytuję istniejący model z: {model_path}")
        model = PPO.load(
            model_path,
            env=env,
            tensorboard_log=config["tensorboard_dir"],
        )
        print("✅ Model wczytany!")
    else:
        print("🧠 Tworzę nowy model PPO...")
        model = PPO(
            "MlpPolicy",
            env,
            verbose=1,
            tensorboard_log=config["tensorboard_dir"],
            learning_rate=config["learning_rate"],
            n_steps=config["n_steps"],
            batch_size=config["batch_size"],
            n_epochs=config["n_epochs"],
            gamma=config["gamma"],
            gae_lambda=config["gae_lambda"],
            clip_range=config["clip_range"],
            ent_coef=config["ent_coef"],
            vf_coef=config["vf_coef"],
            max_grad_norm=config["max_grad_norm"],
        )
        print("✅ Model utworzony!")
    
    # Callbacki
    os.makedirs(config["model_dir"], exist_ok=True)
    
    checkpoint_callback = CheckpointCallback(
        save_freq=config["save_freq"],
        save_path=config["model_dir"],
        name_prefix="ppo_hexwars",
    )
    
    callbacks = [checkpoint_callback]
    
    # Opcjonalnie: ewaluacja
    if config.get("eval_freq", 0) > 0:
        eval_env = create_vec_env(config)
        eval_callback = EvalCallback(
            eval_env,
            best_model_save_path=os.path.join(config["model_dir"], "best_model"),
            log_path=config["log_dir"],
            eval_freq=config["eval_freq"],
            n_eval_episodes=5,
            deterministic=True,
        )
        callbacks.append(eval_callback)
    
    # Trening
    print("\n🎯 ROZPOCZYNAM TRENING...\n")
    
    try:
        model.learn(
            total_timesteps=config["total_timesteps"],
            callback=callbacks,
            log_interval=10,
            progress_bar=True,
        )
        
        print("\n✅ TRENING ZAKOŃCZONY!")
        
        # Zapisz finalny model
        final_model_path = os.path.join(config["model_dir"], "ppo_hexwars_final.zip")
        model.save(final_model_path)
        print(f"💾 Model zapisany: {final_model_path}")
        
        # Zapisz vectorized env (jeśli normalizacja)
        if config.get("normalize", False):
            vec_normalize_path = os.path.join(config["model_dir"], "vec_normalize_final.pkl")
            env.save(vec_normalize_path)
            print(f"💾 VecNormalize zapisane: {vec_normalize_path}")
    
    except KeyboardInterrupt:
        print("\n⚠️ Trening przerwany przez użytkownika (Ctrl+C)")
        
        # Zapisz model przed wyjściem
        interrupted_model_path = os.path.join(config["model_dir"], "ppo_hexwars_interrupted.zip")
        model.save(interrupted_model_path)
        print(f"💾 Model zapisany: {interrupted_model_path}")
    
    finally:
        # Zamknij środowisko
        env.close()
        print("📚 Środowisko zamknięte")


# ============================================================================
# TEST (opcjonalny)
# ============================================================================

def test(config: dict):
    """
    Testuj wytrenowany model.
    """
    print("=" * 70)
    print("🧪 TEST MODELU")
    print("=" * 70)
    
    model_path = config.get("test_model", None)
    if not model_path or not os.path.exists(model_path):
        print(f"❌ Model nie znaleziony: {model_path}")
        return
    
    print(f"📂 Wczytuję model z: {model_path}")
    
    # Utwórz środowisko
    env = create_env(config)
    
    # Wczytaj model
    model = PPO.load(model_path)
    print("✅ Model wczytany!")
    
    # Test
    n_episodes = config.get("test_episodes", 5)
    print(f"\n🎮 Testuję {n_episodes} epizodów...\n")
    
    for episode in range(n_episodes):
        obs, info = env.reset()
        done = False
        total_reward = 0
        steps = 0
        
        print(f"--- Epizod {episode + 1} ---")
        
        while not done:
            action, _states = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, info = env.step(action)
            done = terminated or truncated
            
            total_reward += reward
            steps += 1
            
            if steps % 50 == 0:
                print(f"  Krok {steps}: nagroda = {reward:.2f}")
        
        print(f"✅ Zakończono: {steps} kroków, całkowita nagroda = {total_reward:.2f}\n")
    
    env.close()
    print("📚 Test zakończony!")


# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="Trening RL dla gry strategicznej hex")
    
    # Tryby
    parser.add_argument("--mode", type=str, default="train", choices=["train", "test"],
                        help="Tryb: train (trening) lub test (testowanie modelu)")
    parser.add_argument("--editor", action="store_true",
                        help="Tryb edytora (brak .exe, uruchom grę z Godot)")
    
    # Ścieżki
    parser.add_argument("--project-dir", type=str, default=".",
                        help="Katalog projektu")
    parser.add_argument("--env-path", type=str, default=None,
                        help="Ścieżka do .exe gry (None = tryb edytora)")
    parser.add_argument("--model-dir", type=str, default="models",
                        help="Katalog do zapisu modeli")
    parser.add_argument("--log-dir", type=str, default="logs",
                        help="Katalog do logów")
    parser.add_argument("--tensorboard-dir", type=str, default="runs/tensorboard",
                        help="Katalog do tensorboard")
    
    # Środowisko
    parser.add_argument("--n-envs", type=int, default=1,
                        help="Liczba równoległych środowisk")
    parser.add_argument("--port", type=int, default=10008,
                        help="Port dla Godot")
    parser.add_argument("--show-window", action="store_true",
                        help="Pokaż okno gry")
    parser.add_argument("--timeout", type=int, default=60,
                        help="Timeout połączenia w sekundach")
    parser.add_argument("--normalize", action="store_true",
                        help="Normalizuj obserwacje i nagrody")
    
    # Trening
    parser.add_argument("--total-timesteps", type=int, default=50_000,
                        help="Całkowita liczba kroków treningu")
    parser.add_argument("--save-freq", type=int, default=10_000,
                        help="Częstotliwość zapisu modelu")
    parser.add_argument("--eval-freq", type=int, default=0,
                        help="Częstotliwość ewaluacji (0 = wyłączone)")
    parser.add_argument("--continue-from", type=str, default=None,
                        help="Kontynuuj trening z modelu")
    
    # Hiperparametry PPO
    parser.add_argument("--learning-rate", type=float, default=3e-4,
                        help="Learning rate")
    parser.add_argument("--n-steps", type=int, default=128,
                        help="Liczba kroków per rollout")
    parser.add_argument("--batch-size", type=int, default=512,
                        help="Batch size")
    parser.add_argument("--n-epochs", type=int, default=10,
                        help="Liczba epok optymalizacji")
    parser.add_argument("--gamma", type=float, default=0.99,
                        help="Discount factor")
    parser.add_argument("--gae-lambda", type=float, default=0.95,
                        help="GAE lambda")
    parser.add_argument("--clip-range", type=float, default=0.2,
                        help="PPO clip range")
    parser.add_argument("--ent-coef", type=float, default=0.01,
                        help="Entropy coefficient")
    parser.add_argument("--vf-coef", type=float, default=0.5,
                        help="Value function coefficient")
    parser.add_argument("--max-grad-norm", type=float, default=0.5,
                        help="Max gradient norm")
    
    # Test
    parser.add_argument("--test-model", type=str, default=None,
                        help="Ścieżka do modelu do testowania")
    parser.add_argument("--test-episodes", type=int, default=5,
                        help="Liczba epizodów testowych")
    
    args = parser.parse_args()
    
    # Przygotuj config
    config = {
        "project_dir": os.path.abspath(args.project_dir),
        "env_path": args.env_path,
        "model_dir": os.path.join(args.project_dir, args.model_dir),
        "log_dir": os.path.join(args.project_dir, args.log_dir),
        "tensorboard_dir": os.path.join(args.project_dir, args.tensorboard_dir),
        
        "n_envs": args.n_envs,
        "port": args.port,
        "show_window": args.show_window,
        "seed": int(time.time()),
        "timeout_wait": args.timeout,
        "normalize": args.normalize,
        
        "total_timesteps": args.total_timesteps,
        "save_freq": args.save_freq,
        "eval_freq": args.eval_freq,
        "continue_from": args.continue_from,
        
        "learning_rate": args.learning_rate,
        "n_steps": args.n_steps,
        "batch_size": args.batch_size,
        "n_epochs": args.n_epochs,
        "gamma": args.gamma,
        "gae_lambda": args.gae_lambda,
        "clip_range": args.clip_range,
        "ent_coef": args.ent_coef,
        "vf_coef": args.vf_coef,
        "max_grad_norm": args.max_grad_norm,
        
        "editor_mode": args.editor or args.env_path is None,
        "test_model": args.test_model,
        "test_episodes": args.test_episodes,
    }
    
    # Uruchom
    if args.mode == "train":
        train(config)
    elif args.mode == "test":
        test(config)


if __name__ == "__main__":
    main()