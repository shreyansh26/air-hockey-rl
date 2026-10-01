"""Reproduce the diagnosis figure from retained checkpoint/probe evidence."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def main():
    fig, axes = plt.subplots(1, 3, figsize=(15, 5), constrained_layout=True)
    fig.suptitle("Bot quality: credit horizon, basic control, and a real incoming shot", fontsize=15)
    colors = ["#c45355", "#df9a35", "#238b78"]
    seconds = np.linspace(0, 15, 300)
    for gamma, color in [(0.99, colors[0]), (0.999, colors[2])]:
        axes[0].plot(seconds, gamma ** (30 * seconds), color=color, label=f"gamma {gamma}")
    axes[0].set(xlabel="Seconds until a +1 goal", ylabel="Discount multiplier", ylim=(0, 1.05), title="30 Hz decisions")
    axes[0].legend(frameon=False)
    names = ["Original PPO", "Warm start", "Revised PPO"]
    files = ["quality-before-v2", "quality-bootstrap-v2", "quality-ppo"]
    reports = [json.loads((ROOT / f"validation/{name}.json").read_text()) for name in files]
    x = np.arange(3)
    axes[1].bar(x - 0.18, [m["defense"]["contact_rate"] * 100 for m in reports], 0.36, color=colors[2], label="Real puck contact")
    axes[1].bar(x + 0.18, [m["defense"]["near_boundary_fraction"] * 100 for m in reports], 0.36, color=colors[0], label="Near boundary")
    axes[1].set(xticks=x, xticklabels=names, ylabel="Percent", ylim=(0, 110), title="200 held-out incoming-shot episodes")
    axes[1].legend(frameon=False, loc="upper left", fontsize=8)
    axes[1].tick_params(axis="x", labelsize=9)
    for i in [0, 2]:
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
    fig.savefig(ROOT / "validation/quality-analysis.png", dpi=170)


if __name__ == "__main__":
    main()
