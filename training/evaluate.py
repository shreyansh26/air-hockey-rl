"""Held-out first-to-seven tournaments; censored matches never become wins."""
import argparse
from hashlib import sha256
import json
import math
from pathlib import Path
import time

import numpy as np
from stable_baselines3 import PPO
import torch

from common import ROOT
from env import make_env


def wilson(wins, count):
    if count == 0:
        return [0.0, 1.0]
    z = 1.959963984540054
    p = wins / count
    centre = (p + z * z / (2 * count)) / (1 + z * z / count)
    half = z * math.sqrt(p * (1 - p) / count + z * z / (4 * count * count)) / (1 + z * z / count)
    return [centre - half, centre + half]


def matchup(bundle, bottom, top, count, args, seed):
    env = make_env(arenas=args.arenas, processes=args.processes, seed=seed,
                   delay=bundle["levels"][bottom]["delay_ticks"], log_dir=ROOT / "training/runs/evaluation")
    learner = PPO.load(bundle["levels"][bottom]["checkpoint"], device="cpu")
    opponents = [] if top == "intercept" else [str(ROOT / f"models/{top}/actor.json")]
    env.env_method("configure", mode="rally", hit_reward=0, shaping=0, limit_ticks=36000,
                   opponent_mode="fixed", opponent_style="intercept", opponents=opponents, evaluation_match=True)
    scores = np.zeros((env.num_envs, 2), int)
    durations = np.zeros(env.num_envs, int)
    wins, losses, censored, stalls, points, hits = 0, 0, 0, 0, 0, 0
    score_differences, lengths, replays = [], [], []
    active = np.arange(env.num_envs) < min(env.num_envs, count)
    assigned = int(active.sum())
    started = time.perf_counter()
    try:
        obs = env.reset()
        steps = 0
        while wins + losses + censored < count:
            actions, _ = learner.predict(obs, deterministic=True)
            obs, rewards, dones, infos = env.step(actions)
            durations[active] += 1
            steps += 1
            if steps % 30 == 0 and len(replays) < 200:
                replays.append({"decision": steps, "observation": obs[0].tolist(), "action": actions[0].tolist(), "scores": scores[0].tolist()})
            for i in np.flatnonzero(active):
                if dones[i]:
                    winner = infos[i].get("winner", -1)
                    stalls += infos[i].get("stalls", 0)
                    hits += infos[i].get("hits", 0)
                    if winner >= 0:
                        scores[i, winner] += 1
                        points += 1
                finished = np.max(scores[i]) >= 7
                timed_out = durations[i] >= args.max_decisions
                if finished or timed_out:
                    if finished:
                        wins += int(scores[i, 0] == 7)
                        losses += int(scores[i, 1] == 7)
                        score_differences.append(int(scores[i, 0] - scores[i, 1]))
                    else:
                        censored += 1
                    lengths.append(int(durations[i]))
                    scores[i] = 0
                    durations[i] = 0
                    if assigned < count:
                        assigned += 1
                    else:
                        active[i] = False
        return {"bottom": bottom, "top": top, "seed": seed, "requested_matches": count, "wins": wins, "losses": losses,
                "censored": censored, "win_rate": wins / max(1, wins + losses), "wilson_95": wilson(wins, wins + losses),
                "mean_score_difference": float(np.mean(score_differences)) if score_differences else None,
                "mean_match_seconds": float(np.mean(lengths)) / 30, "stalls": stalls, "points": points, "paddle_hits": hits,
                "wall_seconds": time.perf_counter() - started, "replay": replays}
    finally:
        env.close()


def main(args):
    torch.set_num_threads(1)
    bundle = json.loads(Path(args.manifest).read_text())
    reports, gates = [], {}
    levels = ["easy", "medium", "hard", "insane"]
    for i, (weaker, stronger) in enumerate(zip(levels, levels[1:])):
        pair = []
        for bottom, top in [(stronger, weaker), (weaker, stronger)]:
            report = matchup(bundle, bottom, top, args.matches // 2, args, 910000 + i * 10000)
            pair.append(report)
            reports.append(report)
            print(json.dumps({k: v for k, v in report.items() if k != "replay"}), flush=True)
        wins = pair[0]["wins"] + pair[1]["losses"]
        total = sum(p["wins"] + p["losses"] for p in pair)
        interval = wilson(wins, total)
        gates[f"{stronger}>{weaker}"] = {"wins": wins, "completed": total, "requested": args.matches,
            "win_rate": wins / max(1, total), "wilson_95": interval,
            "passed": args.matches >= 400 and total == args.matches and wins / max(1, total) > 0.55 and interval[0] > 0.5}
    baseline = matchup(bundle, "insane", "intercept", args.matches, args, 990001)
    reports.append(baseline)
    gates["insane_vs_strong_baseline"] = {"win_rate": baseline["win_rate"], "wilson_95": baseline["wilson_95"],
                                           "passed": baseline["censored"] == 0 and baseline["win_rate"] >= 0.8}
    evidence = {"physics_hash": bundle["physics_hash"], "model_hashes": {level: bundle["levels"][level]["weights_sha256"] for level in levels},
                "matches_per_pair": args.matches, "max_match_seconds": args.max_decisions / 30, "gates": gates,
                "qualified": all(gate["passed"] for gate in gates.values()), "human_playtests": "unverified", "matchups": reports}
    destination = ROOT / "validation/difficulty.json"
    destination.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(gates, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="models/manifest.json")
    parser.add_argument("--matches", type=int, default=400)
    parser.add_argument("--arenas", type=int, default=16)
    parser.add_argument("--processes", type=int, default=1)
    parser.add_argument("--max-decisions", type=int, default=9000)
    main(parser.parse_args())
