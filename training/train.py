"""Pinned stock SB3 PPO with curriculum, frozen opponents, checkpoint/resume."""
import argparse
import json
from pathlib import Path
import random
import signal
import time

import numpy as np
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback, CallbackList, CheckpointCallback, EvalCallback
from stable_baselines3.common.logger import configure
import torch

from common import ROOT, physics_hash
from env import make_env
from export_policy import export


class Progress(BaseCallback):
    def __init__(self, output, config):
        super().__init__()
        self.output, self.config = output, config
        self.rows = []
        self.started = time.perf_counter()
        self.last_end = self.started
        self.phase = None
        self.pool = []
        self.next_freeze = config.get("freeze_every", 100000)

    def _on_step(self):
        return True

    def _on_rollout_start(self):
        now = time.perf_counter()
        self.update_seconds = now - self.last_end
        self.rollout_started = now
        progress = self.model.num_timesteps
        stage = next((stage for stage in self.config["curriculum"] if progress < stage["until"]), self.config["curriculum"][-1])
        if self.phase != stage:
            self.training_env.env_method("configure", mode=stage["mode"], hit_reward=stage.get("hit_reward", 0), shaping=stage.get("shaping", 0), drill_bonus=stage.get("drill_bonus", 0), gamma=self.config["ppo"]["gamma"])
            self.phase = stage.copy()
        if progress >= self.next_freeze:
            checkpoint = self.output / f"frozen-{progress}.zip"
            self.model.save(checkpoint)
            directory = self.output / f"opponent-{progress}"
            export(checkpoint, directory, "frozen", self.config["delay_ticks"])
            self.pool.append("res://" + directory.relative_to(ROOT).as_posix() + "/actor.json")
            self.pool = self.pool[-4:]
            self.training_env.env_method("configure", opponents=self.pool)
            (self.output / "opponents.json").write_text(json.dumps(self.pool, indent=2))
            self.next_freeze += self.config.get("freeze_every", 100000)

    def _on_rollout_end(self):
        self.last_end = time.perf_counter()
        row = {"transitions": self.model.num_timesteps, "rollout_seconds": self.last_end - self.rollout_started,
               "ppo_update_seconds": self.update_seconds, "phase": self.phase["mode"], "reward_config": self.phase,
               "elapsed_seconds": self.last_end - self.started,
               "mean_episode_reward": float(np.mean([e["r"] for e in self.model.ep_info_buffer])) if self.model.ep_info_buffer else None}
        self.rows.append(row)
        (self.output / "timings.json").write_text(json.dumps(self.rows, indent=2) + "\n")


def train(config, resume=None, warm_start=None):
    if resume and warm_start:
        raise ValueError("Choose optimizer-preserving resume or a fresh warm start")
    torch.set_num_threads(config.get("torch_threads", 1))
    output = ROOT / config["output"]
    output.mkdir(parents=True, exist_ok=True)
    (output / "config.json").write_text(json.dumps({**config, "physics_hash": physics_hash(), "warm_start": warm_start, "resume": resume}, indent=2) + "\n")
    env = make_env(arenas=config["arenas"], processes=config.get("processes", 1), seed=config["seed"], delay=config["delay_ticks"], log_dir=output)
    evaluation = None
    model = None
    progress = Progress(output, config)
    try:
        policy_kwargs = {"net_arch": {"pi": [64, 64], "vf": [64, 64]}, "activation_fn": torch.nn.Tanh, "log_std_init": config.get("log_std_init", 0)}
        if resume:
            old_config = Path(resume).parent / "config.json"
            if old_config.exists() and json.loads(old_config.read_text()).get("physics_hash") != physics_hash():
                raise ValueError("Resume checkpoint uses different physics; retrain instead")
            model = PPO.load(resume, env=env, device=config.get("device", "cpu"), **config["ppo"])
            rng_path = Path(resume).parent / "rng.pt"
            if rng_path.exists():
                state = torch.load(rng_path, weights_only=False)
                torch.set_rng_state(state["torch"])
                np.random.set_state(state["numpy"])
                random.setstate(state["python"])
            engine_rng_path = Path(resume).parent / "godot-rng.json"
            if engine_rng_path.exists():
                batches = json.loads(engine_rng_path.read_text())
                for client, states in zip(env.venv.clients, batches):
                    if len(states) == client.num_envs:
                        client.command("configure", rng_states=states)
        else:
            model = PPO("MlpPolicy", env, device=config.get("device", "cpu"), seed=config["seed"], policy_kwargs=policy_kwargs,
                        verbose=1, **config["ppo"])
            if warm_start:
                old_config = Path(warm_start).parent / "config.json"
                if not old_config.exists() or json.loads(old_config.read_text()).get("physics_hash") != physics_hash():
                    raise ValueError("Warm-start checkpoint needs matching recorded physics")
                source = PPO.load(warm_start, device="cpu")
                copied = {key: value for key, value in source.policy.state_dict().items() if key != "log_std"}
                missing, unexpected = model.policy.load_state_dict(copied, strict=False)
                assert missing == ["log_std"] and not unexpected
                model.set_random_seed(config["seed"])
        model.set_logger(configure(str(output), ["stdout", "csv", "tensorboard"]))
        total_envs = env.num_envs
        callbacks = [progress, CheckpointCallback(save_freq=max(1, config.get("checkpoint_every", 50000) // total_envs), save_path=str(output), name_prefix="ppo")]
        if config.get("eval_every", 0):
            evaluation = make_env(arenas=4, seed=900001, delay=config["delay_ticks"], log_dir=output / "evaluation")
            evaluation.env_method("configure", mode="rally", shaping=0, hit_reward=0)
            callbacks.append(EvalCallback(evaluation, best_model_save_path=str(output / "best"), log_path=str(output), eval_freq=max(1, config["eval_every"] // total_envs), n_eval_episodes=20, deterministic=True))
        pool_path = Path(resume).parent / "opponents.json" if resume else output / "opponents.json"
        if pool_path.exists():
            progress.pool = json.loads(pool_path.read_text())
            env.env_method("configure", opponents=progress.pool)
        remaining = max(0, config["transitions"] - model.num_timesteps)
        model.learn(remaining, callback=CallbackList(callbacks), reset_num_timesteps=not bool(resume))
    except KeyboardInterrupt:
        print("Interrupted: saving optimizer, RNG and opponent pool")
    finally:
        if model:
            model.save(output / "final.zip")
            torch.save({"torch": torch.get_rng_state(), "numpy": np.random.get_state(), "python": random.getstate()}, output / "rng.pt")
            (output / "opponents.json").write_text(json.dumps(progress.pool, indent=2) + "\n")
            raw = env.venv
            engine_states = []
            for client in raw.clients:
                try:
                    engine_states.append([state["rng_state"] for state in client.command("inspect")["states"]])
                except OSError:
                    engine_states.append([]) # A failed transport still leaves a usable SB3/RNG checkpoint.
            (output / "godot-rng.json").write_text(json.dumps(engine_states, indent=2) + "\n")
            report = {"transitions": model.num_timesteps, "wall_seconds": time.perf_counter() - progress.started,
                      "bridge_seconds": raw.bridge_seconds, "physics_hash": physics_hash(), "seed": config["seed"],
                      "delay_ticks": config["delay_ticks"], "checkpoint": str(output / "final.zip")}
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps(report, indent=2))
        env.close()
        if evaluation:
            evaluation.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--resume")
    parser.add_argument("--warm-start", help="Copy actor/critic weights into a fresh stock PPO optimizer/exploration distribution")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--delay", type=int)
    parser.add_argument("--output")
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text())
    for key, value in [("seed", args.seed), ("delay_ticks", args.delay), ("output", args.output)]:
        if value is not None:
            config[key] = value
    train(config, args.resume, args.warm_start)
