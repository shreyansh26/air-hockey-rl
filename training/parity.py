"""Collect >=10k real Godot observations; compare SB3/ONNX/GDScript actors."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import subprocess

import numpy as np
import onnxruntime as ort
from stable_baselines3 import PPO
import torch

from common import ROOT, LEVEL_DELAYS
from env import make_env


def collect(checkpoint):
    fixtures = ROOT / "checks/fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    model = PPO.load(checkpoint, device="cpu")
    env = make_env(arenas=16, seed=900123, log_dir=ROOT / "training/runs/parity")
    observations = []
    try:
        env.env_method("configure", mode="mixed", hit_reward=0, shaping=0)
        obs = env.reset()
        for _ in range(625):
            observations.append(obs.copy())
            actions, _ = model.predict(obs, deterministic=True)
            obs, _, _, _ = env.step(actions)
    finally:
        env.close()
    values = np.concatenate(observations).astype("<f4")
    assert values.shape == (10000, 52) and np.isfinite(values).all()
    (fixtures / "observations.bin").write_bytes(values.tobytes())
    return values


def main(manifest_path):
    torch.set_num_threads(1)
    bundle = json.loads(Path(manifest_path).read_text())
    values = collect(bundle["levels"]["insane"]["checkpoint"])
    reports = {}
    for level, profile in bundle["levels"].items():
        model = PPO.load(profile["checkpoint"], device="cpu")
        expected, _ = model.predict(values, deterministic=True)
        session = ort.InferenceSession(str(ROOT / f"models/{level}/actor.onnx"), providers=["CPUExecutionProvider"])
        actual = session.run(None, {"observation": values})[0]
        error = float(np.max(np.abs(expected - actual)))
        assert error <= 1e-4, (level, error)
        (ROOT / f"checks/fixtures/{level}.bin").write_bytes(expected.astype("<f4").tobytes())
        reports[level] = {"sb3_onnx_max_abs_error": error}
    metadata = {"observations": 10000, "real_rollout_observations": 10000, "seed": 900123,
                "observations_sha256": sha256(values.tobytes()).hexdigest(), "levels": reports}
    (ROOT / "checks/fixtures/manifest.json").write_text(json.dumps(metadata, indent=2))
    result = subprocess.run([str(ROOT / "tools/godot"), "--headless", "--path", str(ROOT), "--script", "checks/parity_check.gd"], capture_output=True, text=True, check=True)
    line = next(line for line in result.stdout.splitlines() if line.startswith("PARITY "))
    metadata["godot"] = json.loads(line[7:])
    (ROOT / "validation/parity.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="models/manifest.json")
    main(parser.parse_args().manifest)
