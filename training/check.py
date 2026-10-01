"""Small runnable contract checks, including real PPO updates and Godot ticks."""
import json
from pathlib import Path
import time

import gymnasium as gym
import numpy as np
from stable_baselines3 import PPO
import torch

from env import ROOT, make_env


def main():
    torch.set_num_threads(1)
    output = ROOT / "training/runs/check"
    output.mkdir(parents=True, exist_ok=True)
    pendulum = PPO("MlpPolicy", "Pendulum-v1", n_steps=128, batch_size=64, n_epochs=2, seed=17, device="cpu")
    pendulum.learn(256)
    pendulum.save(output / "pendulum")
    restored = PPO.load(output / "pendulum", device="cpu")
    assert restored.num_timesteps == 256 and restored.policy.optimizer.state_dict()["state"]
    pendulum.get_env().close()
    env = make_env(arenas=2, seed=123, log_dir=output)
    raw = env.venv
    try:
        env.seed(17)
        obs = env.reset()
        assert obs.shape == (2, 52) and obs.dtype == np.float32
        assert len(env.reset_infos) == 2
        states = raw.client.command("inspect")["states"]
        assert len({s["world"] for s in states}) == 2
        raw.client.command("fixture", case="travel", index=0)
        env.step(np.zeros((2, 2), np.float32))
        states = raw.client.command("inspect")["states"]
        assert states[0]["ticks"] == 4
        travel = states[0]["puck"][0] - 300
        assert abs(travel - 120 / 30) < 0.05, travel
        time.sleep(0.05)
        assert raw.client.command("inspect")["states"][0]["ticks"] == 4
        raw.client.command("configure", limit_ticks=8)
        env.reset()
        _, _, dones, _ = env.step(np.zeros((2, 2), np.float32))
        assert not dones.any()
        reset, _, dones, infos = env.step(np.zeros((2, 2), np.float32))
        assert dones.all() and all(info["TimeLimit.truncated"] for info in infos)
        assert all(info["terminal_observation"].shape == (52,) for info in infos)
        assert any(not np.array_equal(reset[i], infos[i]["terminal_observation"]) for i in range(2))
        raw.client.command("configure", limit_ticks=1440)
        env.reset()
        raw.client.command("fixture", case="goal", index=0)
        _, _, dones, infos = env.step(np.zeros((2, 2), np.float32))
        assert dones[0] and not infos[0]["TimeLimit.truncated"] and not dones[1]
        assert infos[0]["winner"] == 0 and infos[0]["physics_ticks"] < 4
        model = PPO("MlpPolicy", env, n_steps=128, batch_size=64, n_epochs=2, seed=17, device="cpu",
                    policy_kwargs={"net_arch": {"pi": [64, 64], "vf": [64, 64]}, "activation_fn": torch.nn.Tanh})
        before = model.policy.action_net.weight.detach().clone()
        model.learn(256)
        assert not torch.equal(before, model.policy.action_net.weight)
        model.save(output / "godot")
        loaded = PPO.load(output / "godot", env=env, device="cpu")
        assert loaded.policy.optimizer.state_dict()["state"]
        loaded.learn(256, reset_num_timesteps=False)
        assert loaded.num_timesteps == 512
        pid = raw.client.proc.pid
    finally:
        env.close()
    assert raw.client.proc.poll() is not None
    timings = []
    for count in [16, 32, 64]:
        env = make_env(arenas=count, seed=123, log_dir=output)
        try:
            env.reset()
            action = np.zeros((count, 2), np.float32)
            started = time.perf_counter()
            for _ in range(128):
                env.step(action)
            elapsed = time.perf_counter() - started
            timings.append({"arenas": count, "transitions": 128 * count, "seconds": elapsed,
                            "transitions_per_second": 128 * count / elapsed,
                            "simulation_seconds_per_wall_second_per_arena": 128 / 30 / elapsed})
        finally:
            env.close()
    report = {"pendulum_ppo": "passed", "godot_ppo_resume": "passed", "batch_dtype_reset_terminal": "passed",
              "terminal_mid_action": "passed", "exact_four_ticks": "passed", "travel": travel,
              "frozen_while_waiting": "passed", "independent_worlds": "passed", "child_cleanup": "passed",
              "batch_benchmarks": timings, "device": "cpu", "torch_threads": 1}
    path = ROOT / "validation/bridge.json"
    path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
