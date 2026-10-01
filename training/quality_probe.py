"""Held-out basic shot returns and rally points; rewards are not skill metrics."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import time

import numpy as np
from stable_baselines3 import PPO
import torch

from bootstrap import teacher
from common import ROOT, physics_hash
from env import make_env


def probe(args):
    torch.set_num_threads(1)
    model = None if args.teacher else PPO.load(args.checkpoint, device="cpu")
    env = make_env(arenas=16, processes=args.processes, seed=970001, delay=args.delay, log_dir=ROOT / "training/runs/probe")
    report = {"scenario_version": 2, "checkpoint": args.checkpoint, "checkpoint_sha256": sha256(Path(args.checkpoint).read_bytes()).hexdigest() if model else None,
              "teacher": args.teacher, "delay_ticks": args.delay, "physics_hash": physics_hash()}
    try:
        for mode in ["defense", "rally"]:
            env.env_method("configure", mode=mode, hit_reward=0, shaping=0, drill_bonus=0, opponent_mode="fixed",
                           opponent_style="center" if mode == "defense" else "intercept", opponents=[], limit_ticks=3600)
            obs = env.reset()
            hits, wins, losses, timeouts, ticks, boundary, decisions = 0, 0, 0, 0, 0, 0, 0
            started = time.perf_counter()
            trace, traced_episodes = [], 0
            while wins + losses + timeouts < args.episodes:
                actions = teacher(obs) if args.teacher else model.predict(obs, deterministic=True)[0]
                if args.trace and traced_episodes < 2 and len(trace) < 240:
                    actual = env.venv.clients[0].command("inspect")["states"][0]
                    trace.append({"episode": traced_episodes, "state": actual, "observation": obs[0].tolist(), "action": actions[0].tolist()})
                boundary += int(np.count_nonzero((np.abs(obs[:, 40]) > 0.82) | (obs[:, 41] < 0.13) | (obs[:, 41] > 0.9)))
                decisions += env.num_envs
                obs, _, dones, infos = env.step(actions)
                traced_episodes += int(dones[0])
                for i in np.flatnonzero(dones):
                    if wins + losses + timeouts >= args.episodes:
                        break
                    info = infos[i]
                    hits += int(info.get("hits", 0) > 0)
                    winner = info.get("winner", -1)
                    wins += int(winner == 0)
                    losses += int(winner == 1)
                    timeouts += int(winner < 0)
                    ticks += info["physics_ticks"]
            report[mode] = {"episodes": args.episodes, "episodes_with_puck_contact": hits,
                "contact_rate": hits / args.episodes, "scored": wins, "conceded": losses, "timeouts_or_stalls": timeouts,
                "mean_seconds": ticks / 120 / args.episodes, "near_boundary_fraction": boundary / decisions,
                "wall_seconds": time.perf_counter() - started}
            if args.trace:
                report[mode]["trajectory"] = trace
            print(json.dumps({key: value for key, value in report[mode].items() if key != "trajectory"}), flush=True)
    finally:
        env.close()
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", default="training/runs/full-remote/final.zip")
    parser.add_argument("--teacher", action="store_true")
    parser.add_argument("--delay", type=int, default=10)
    parser.add_argument("--episodes", type=int, default=200)
    parser.add_argument("--processes", type=int, default=1)
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--output", default="validation/quality-probe.json")
    probe(parser.parse_args())
