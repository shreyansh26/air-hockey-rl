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

from common import ROOT, physics_hash
from env import make_env


def wilson(wins, count):
    if count == 0:
        return [0.0, 1.0]
    z = 1.959963984540054
    p = wins / count
    centre = (p + z * z / (2 * count)) / (1 + z * z / count)
    half = z * math.sqrt(p * (1 - p) / count + z * z / (4 * count * count)) / (1 + z * z / count)
    return [centre - half, centre + half]


def matchup(bundle, bottom, top, count, args, seed, learner_side=0):
    env = make_env(arenas=args.arenas, processes=args.processes, seed=seed,
                   delay=bundle["levels"][bottom]["delay_ticks"], log_dir=ROOT / "training/runs/evaluation")
    learner = PPO.load(bundle["levels"][bottom]["checkpoint"], device="cpu")
    scripted = top in ["intercept", "delayed_chase", "puck_chase", "center", "chase"]
    opponents = [] if scripted else [str(ROOT / bundle["levels"][top].get("actor_manifest", f"models/{top}/actor.json"))]
    env.env_method("configure", mode="rally", hit_reward=0, shaping=0, limit_ticks=args.max_decisions * 4 + 4,
                   opponent_mode="fixed", opponent_style=top if scripted else "intercept", opponent_delay=args.opponent_delay,
                   opponents=opponents, evaluation_match=True, learner_side=learner_side, drill_bonus=0)
    scores = np.zeros((env.num_envs, 2), int)
    durations = np.zeros(env.num_envs, int)
    wins, losses, censored, stalls, points, hits, rally_timeouts = 0, 0, 0, 0, 0, 0, 0
    score_differences, lengths, replays = [], [], []
    quotas = np.full(env.num_envs, count // env.num_envs) + (np.arange(env.num_envs) < count % env.num_envs)
    completed = np.zeros(env.num_envs, int)
    active = quotas > 0
    started = time.perf_counter()
    try:
        obs = env.reset()
        steps = 0
        while wins + losses + censored < count:
            actions, _ = learner.predict(obs, deterministic=True)
            obs, rewards, dones, infos = env.step(actions)
            durations[active] += 1
            steps += 1
            restart = []
            if steps % 30 == 0 and len(replays) < 200:
                replays.append({"decision": steps, "observation": obs[0].tolist(), "action": actions[0].tolist(), "scores": scores[0].tolist()})
            for i in np.flatnonzero(active):
                if dones[i]:
                    winner = infos[i].get("winner", -1)
                    stalls += infos[i].get("stalls", 0)
                    hits += infos[i].get("hits", 0)
                    rally_timeouts += int(infos[i].get("TimeLimit.truncated", False) and not infos[i].get("stalls", 0))
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
                    completed[i] += 1
                    if completed[i] >= quotas[i]:
                        active[i] = False
                    elif timed_out and not finished:
                        restart.append(i)
            for index, observation in env.venv.restart_matches(restart).items():
                obs[index] = observation
        assert rally_timeouts == 0, "A live nominal rally must not be restarted by an artificial episode limit"
        return {"bottom": bottom, "top": top, "seed": seed, "requested_matches": count, "wins": wins, "losses": losses,
                "censored": censored, "win_rate": wins / max(1, wins + losses), "wilson_95": wilson(wins, wins + losses),
                "mean_score_difference": float(np.mean(score_differences)) if score_differences else None,
                "mean_match_seconds": float(np.mean(lengths)) / 30, "stalls": stalls, "points": points, "paddle_hits": hits,
                "learner_side": learner_side, "opponent_delay_ticks": args.opponent_delay if top in ["delayed_chase", "puck_chase"] else 0 if scripted else bundle["levels"][top]["delay_ticks"],
                "opponent_observation_scope": "puck_only" if top == "puck_chase" else "whole_world" if top == "delayed_chase" or not scripted else "instantaneous",
                "artificial_rally_timeouts": rally_timeouts, "duration_scope": "active rally simulation; excludes countdown and goal presentation",
                "wall_seconds": time.perf_counter() - started, "replay": replays}
    finally:
        env.close()


def main(args):
    torch.set_num_threads(1)
    bundle = json.loads(Path(args.manifest).read_text())
    if bundle["physics_hash"] != physics_hash():
        raise ValueError("Tournament manifest does not match the running Arena source")
    checked_levels = ["insane"] if args.baseline_only else list(bundle["levels"])
    for level in checked_levels:
        profile = bundle["levels"][level]
        if sha256(Path(profile["checkpoint"]).read_bytes()).hexdigest() != profile["checkpoint_sha256"]:
            raise ValueError("Evaluation checkpoint hash mismatch: " + level)
        if not args.baseline_only:
            path = ROOT / profile.get("actor_manifest", f"models/{level}/actor.json")
            actor = json.loads(path.read_text())
            if actor["weights_sha256"] != profile["weights_sha256"] or actor["delay_ticks"] != profile["delay_ticks"] or actor["physics_hash"] != bundle["physics_hash"]:
                raise ValueError("Evaluation opponent/profile mismatch: " + level)
    reports, gates = [], {}
    levels = ["easy", "medium", "hard", "insane"]
    for i, (weaker, stronger) in enumerate([] if args.baseline_only else zip(levels, levels[1:])):
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
    for style in args.baselines:
        pair = [matchup(bundle, "insane", style, args.matches // 2, args, 990001, side) for side in [0, 1]]
        reports.extend(pair)
        wins = sum(p["wins"] for p in pair)
        total = sum(p["wins"] + p["losses"] for p in pair)
        key = "insane_vs_strong_baseline" if style == "intercept" else "insane_vs_" + style
        gates[key] = {"wins": wins, "completed": total, "requested": args.matches, "win_rate": wins / max(1, total),
                      "wilson_95": wilson(wins, total), "passed": args.matches >= 400 and total == args.matches and wins / max(1, total) >= 0.8}
        print(json.dumps({key: gates[key]}), flush=True)
    evidence = {"physics_hash": bundle["physics_hash"], "model_hashes": {level: bundle["levels"][level]["weights_sha256"] for level in levels},
                "checkpoint_hashes": {level: bundle["levels"][level]["checkpoint_sha256"] for level in levels},
                "training_physics_hashes": {level: bundle["levels"][level].get("training_physics_hash", bundle["physics_hash"]) for level in levels},
                "matches_per_pair": args.matches, "max_match_seconds": args.max_decisions / 30, "gates": gates,
                "scope": "baseline-only" if args.baseline_only else "full-difficulty-tournament",
                "qualified": not args.baseline_only and all(gate["passed"] for gate in gates.values()), "human_playtests": "unverified", "matchups": reports}
    destination = Path(args.output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(gates, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="models/manifest.json")
    parser.add_argument("--matches", type=int, default=400)
    parser.add_argument("--arenas", type=int, default=16)
    parser.add_argument("--processes", type=int, default=1)
    parser.add_argument("--max-decisions", type=int, default=9000)
    parser.add_argument("--baselines", nargs="+", choices=["intercept", "delayed_chase", "puck_chase", "chase", "center"], default=["intercept"])
    parser.add_argument("--opponent-delay", type=int, default=22)
    parser.add_argument("--baseline-only", action="store_true")
    parser.add_argument("--output", default=str(ROOT / "validation/difficulty.json"))
    args = parser.parse_args()
    if args.matches < 2 or args.matches % 2:
        parser.error("matches must be positive and even for balanced sides")
    main(args)
