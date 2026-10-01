"""Reproduce the diagnosis figure from retained checkpoint/probe evidence."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def main(suffix="v3", output="validation/quality-analysis.png"):
    fig, axes = plt.subplots(1, 3, figsize=(15, 5), constrained_layout=True)
    fig.suptitle("Bot quality: credit horizon, basic control, and a real incoming shot", fontsize=15)
    colors = ["#c45355", "#df9a35", "#559fc1", "#238b78"]
    seconds = np.linspace(0, 15, 300)
    for gamma, color in [(0.99, colors[0]), (0.999, colors[2])]:
        axes[0].plot(seconds, gamma ** (30 * seconds), color=color, label=f"gamma {gamma}")
    axes[0].set(xlabel="Seconds until a +1 goal", ylabel="Discount multiplier", ylim=(0, 1.05), title="30 Hz decisions")
    axes[0].legend(frameon=False)
    names = ["Original PPO", "Warm start", "Revised PPO", "Selected Insane"]
    files = [f"quality-{stage}-{suffix}" for stage in ["before", "bootstrap", "ppo", "selected"]]
    reports = [json.loads((ROOT / f"validation/{name}.json").read_text()) for name in files]
    assert len({tuple(m[key] for key in ["physics_hash", "scenario_version", "seed", "delay_ticks"]) for m in reports}) == 1, "Probe rules, scenario, seeds, and delays must match"
    panel = reports[0]["defense"]
    assert all(m["defense"]["world_quotas"] == panel["world_quotas"] and {k: v["episodes"] for k, v in m["defense"]["shot_groups"].items()} == {k: v["episodes"] for k, v in panel["shot_groups"].items()} for m in reports), "Shot panels must match"
    x = np.arange(4)
    axes[1].bar(x - 0.24, [m["defense"]["contact_rate"] * 100 for m in reports], 0.24, color=colors[2], label="Real puck contact")
    axes[1].bar(x, [m["defense"]["verified_returns"] / m["defense"]["episodes"] * 100 for m in reports], 0.24, color=colors[3], label="Verified return")
    axes[1].bar(x + 0.24, [m["defense"]["near_boundary_fraction"] * 100 for m in reports], 0.24, color=colors[0], label="Near boundary")
    axes[1].set(xticks=x, xticklabels=names, ylabel="Percent", ylim=(0, 110), title=f"{panel['episodes']} held-out incoming-shot episodes")
    axes[1].legend(frameon=False, loc="upper left", fontsize=8)
    axes[1].tick_params(axis="x", labelsize=9)
    for i in [0, 3]:
        trace = json.loads((ROOT / reports[i]["defense"]["trajectory_file"]).read_text())
        trace = [row for row in trace if row["episode"] == 0]
        puck = np.array([row["state"]["puck"] for row in trace])
        paddle = np.array([row["state"]["paddle"] for row in trace])
        axes[2].plot(puck[:, 0], puck[:, 1], "--", color=colors[i], alpha=0.65, linewidth=1)
        axes[2].plot(paddle[:, 0], paddle[:, 1], color=colors[i], linewidth=2, label=names[i] + " paddle")
        axes[2].scatter(paddle[0, 0], paddle[0, 1], s=40, color=colors[i])
        for row in trace:
            if row["state"]["contacts"][0] > 0:
                axes[2].scatter(*row["state"]["puck"], marker="*", s=100, color=colors[i])
                break
    axes[2].axhline(500, color="#b8c4ce", linewidth=1)
    axes[2].set(xlim=(0, 600), ylim=(1000, 0), xlabel="Table x", ylabel="Table y", title="Same initial shot; dashed lines are puck paths")
    axes[2].set_aspect("equal")
    axes[2].legend(frameon=False, fontsize=8, loc="upper left")
    for ax in axes:
        ax.spines[["top", "right"]].set_visible(False)
        ax.grid(alpha=0.15)
    fig.savefig(ROOT / output, dpi=170)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--suffix", default="v3")
    parser.add_argument("--output", default="validation/quality-analysis.png")
    args = parser.parse_args()
    main(args.suffix, args.output)
