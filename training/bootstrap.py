"""Training-only demonstration warm start; deployment still runs the learned MLP.

The teacher sees the same delayed 52-vector, never live engine/future input.
DAgger collects real shared-Godot states, then stock SB3 PPO fine-tunes the actor.
"""
import argparse
import json
from pathlib import Path
import time

import numpy as np
from stable_baselines3 import PPO
import torch

from common import ROOT, physics_hash
from env import make_env


def reflected_x(x):
    folded = np.mod(x - 18, 1128)
    return 18 + np.where(folded < 564, folded, 1128 - folded)


def shot_direction(obs, puck, own):
    # Training-only candidates: three legal goal lanes, straight or one rail bank.
    # Aim at the fully-cleared goal plane, not y=0 (a bank can miss after y=0).
    goals = np.array([242, 300, 358], np.float32)
    images = np.concatenate([goals, 36 - goals, 1164 - goals])
    delta = np.stack([images[None, :] - puck[:, 0, None], np.broadcast_to(-18 - puck[:, 1, None], (len(obs), 9))], axis=2)
    direction = delta / np.maximum(np.linalg.norm(delta, axis=2, keepdims=True), 1)
    opponent = (obs[:, 44:46] + 1) * [300, 500]
    opponent_velocity = obs[:, 46:48] * 1050
    age = obs[:, 51] * 0.5
    behind = puck[:, None, :] - direction * 90
    preparation = np.linalg.norm(behind - own[:, None, :], axis=2) / 1050
    flight = np.maximum(puck[:, 1, None] - opponent[:, 1, None], 0) / np.maximum(-direction[:, :, 1] * 1800, 1)
    predicted_defender = np.clip(opponent[:, 0, None] + opponent_velocity[:, 0, None] * (age[:, None] + preparation + flight), 44, 556)
    ratio = np.clip((puck[:, 1, None] - opponent[:, 1, None]) / np.maximum(puck[:, 1, None] + 18, 1), 0, 1)
    lane = reflected_x(puck[:, 0, None] + delta[:, :, 0] * ratio)
    blocked_setup = (behind[:, :, 0] < 46) | (behind[:, :, 0] > 554) | (behind[:, :, 1] > 954)
    score = np.abs(lane - predicted_defender) / 100 - 0.15 * (np.arange(9) >= 3) - 0.1 * np.abs(direction[:, :, 0]) - 3 * blocked_setup
    return direction[np.arange(len(obs)), np.argmax(score, axis=1)]


def teacher(observations):
    """Guard incoming trajectories; get behind reachable pucks and strike forward."""
    obs = np.asarray(observations, np.float32)
    state = obs[:, 36:48]
    age = obs[:, 51] * 0.5
    puck = (state[:, :2] + 1) * [300, 500]
    velocity = state[:, 2:4] * 2300
    own = (state[:, 4:6] + 1) * [300, 500]
    own_velocity = state[:, 6:8] * 1050
    puck[:, 0] = reflected_x(puck[:, 0] + velocity[:, 0] * age)
    puck[:, 1] += velocity[:, 1] * age
    own += own_velocity * age[:, None]
    own = np.clip(own, [46, 546], [554, 954])
    target = np.tile([300.0, 850.0], (len(obs), 1))
    incoming = velocity[:, 1] > 40
    travel = np.clip((810 - puck[:, 1]) / np.maximum(velocity[:, 1], 40), 0, 1.5)
    target[incoming, 0] = reflected_x(puck[:, 0] + velocity[:, 0] * travel)[incoming]
    reachable = (puck[:, 1] > 545) & (puck[:, 1] < 965)
    near = reachable & incoming
    target[near, 0] = reflected_x(puck[:, 0] + velocity[:, 0] * 0.06)[near]
    target[near, 1] = (puck[:, 1] + 22)[near]
    attack = reachable & ~incoming & (velocity[:, 1] > -450)
    predicted = puck + velocity * 0.06
    direction = shot_direction(obs, predicted, own)
    behind = predicted - direction * 90
    approach = predicted - own
    approach /= np.maximum(np.linalg.norm(approach, axis=1, keepdims=True), 1)
    lined_up = (np.sum(approach * direction, axis=1) > 0.97) & (np.linalg.norm(predicted - own, axis=1) < 170)
    target[attack] = behind[attack]
    strike = attack & lined_up
    target[strike] = (predicted + direction * 90)[strike]
    # Avoid crossing through a puck while returning from its front side.
    route = attack & (own[:, 1] < puck[:, 1] + 35) & (np.abs(own[:, 0] - puck[:, 0]) < 85)
    target[route, 0] += np.where(own[route, 0] < 300, -110, 110)
    target = np.clip(target, [46, 546], [554, 954])
    action = np.clip((target - own) * 7 / 1050, -1, 1)
    action /= np.maximum(np.linalg.norm(action, axis=1, keepdims=True), 1)
    return action.astype(np.float32)


def check():
    state = np.array([-0.6, 0.3, 0, 0.25, 0, 0.7, 0, 0, 0, -0.7, 0, 0], np.float32)
    obs = np.concatenate([np.tile(state, 4), [0, 0, 10 / 60, 10 / 60]])[None].astype(np.float32)
    action = teacher(obs)
    assert action[0, 0] < -0.3 and action[0, 1] < 0, action
    obs[:, [4, 16, 28, 40]] = 0.9
    obs[:, [1, 13, 25, 37]] = -0.6
    obs[:, [3, 15, 27, 39]] = -0.2
    assert teacher(obs)[0, 0] < 0 # return from the right rail to guard.
    assert np.isfinite(action).all() and np.linalg.norm(action) <= 1.00001
    obs[:, [0, 12, 24, 36]] = 0
    obs[:, [1, 13, 25, 37]] = 0.4
    obs[:, [2, 14, 26, 38, 3, 15, 27, 39, 4, 16, 28, 40]] = 0
    obs[:, [9, 21, 33, 45]] = -0.66
    direction = shot_direction(obs, np.array([[300, 700]]), np.array([[300, 850]]))
    assert abs(direction[0, 0]) > 0.4 and direction[0, 1] < 0 # bank around center defense.
    print("Delayed teacher direction, reflection and motor bounds passed")


def train(args):
    config = json.loads(Path(args.config).read_text())
    torch.set_num_threads(config.get("torch_threads", 1))
    rng = np.random.default_rng(config["seed"])
    torch.manual_seed(config["seed"])
    output = ROOT / args.output
    output.mkdir(parents=True, exist_ok=True)
    env = make_env(arenas=config["arenas"], processes=config.get("processes", 1), seed=config["seed"],
                   delay=config["delay_ticks"], log_dir=output)
    env.env_method("configure", mode="mixed", hit_reward=0, shaping=0, limit_ticks=1440)
    model = PPO("MlpPolicy", env, device="cpu", seed=config["seed"],
                policy_kwargs={"net_arch": {"pi": [64, 64], "vf": [64, 64]}, "activation_fn": torch.nn.Tanh}, **config["ppo"])
    actor_parameters = list(model.policy.mlp_extractor.policy_net.parameters()) + list(model.policy.action_net.parameters())
    optimizer = torch.optim.Adam(actor_parameters, lr=0.001)
    inputs, targets, history = [], [], []
    started = time.perf_counter()
    try:
        obs = env.reset()
        for iteration in range(args.iterations):
            batch_obs, batch_targets = [], []
            for _ in range(256):
                expert = teacher(obs)
                prediction, _ = model.predict(obs, deterministic=True)
                use_student = rng.random((env.num_envs, 1)) < min(0.6, iteration / args.iterations)
                actions = np.where(use_student, prediction, expert) + rng.normal(0, 0.08, expert.shape)
                batch_obs.append(obs.copy())
                batch_targets.append(expert)
                obs, _, _, _ = env.step(np.clip(actions, -1, 1))
            inputs.append(np.concatenate(batch_obs))
            targets.append(np.concatenate(batch_targets))
            x = torch.from_numpy(np.concatenate(inputs))
            y = torch.from_numpy(np.concatenate(targets))
            split = max(1, int(len(x) * 0.95))
            # Keep the tail of the newest rollout unseen by the optimizer.
            for _ in range(8):
                for indices in torch.randperm(split).split(1024):
                    prediction = model.policy.get_distribution(x[indices]).distribution.mean
                    loss = torch.nn.functional.mse_loss(prediction, y[indices])
                    optimizer.zero_grad()
                    loss.backward()
                    optimizer.step()
            with torch.no_grad():
                mse = torch.nn.functional.mse_loss(model.policy.get_distribution(x[split:]).distribution.mean, y[split:]).item()
            history.append({"iteration": iteration, "actual_godot_decisions": len(x), "held_out_action_mse": mse})
            print(json.dumps(history[-1]), flush=True)
        with torch.no_grad():
            model.policy.log_std.fill_(-2) # demonstration prior survives early PPO exploration.
        model.save(output / "final.zip")
        (output / "config.json").write_text(json.dumps({**config, "physics_hash": physics_hash()}, indent=2) + "\n")
        report = {"method": "demonstration warm start on real Godot rollouts; PPO follows separately",
                  "physics_hash": physics_hash(), "seed": config["seed"], "delay_ticks": config["delay_ticks"],
                  "teacher_version": 2, "wall_seconds": time.perf_counter() - started, "history": history, "ppo_transitions": 0}
        (output / "bootstrap.json").write_text(json.dumps(report, indent=2) + "\n")
    finally:
        env.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="training/configs/quality.json")
    parser.add_argument("--output", default="training/runs/bootstrap")
    parser.add_argument("--iterations", type=int, default=12)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    check()
    if not args.check:
        train(args)
