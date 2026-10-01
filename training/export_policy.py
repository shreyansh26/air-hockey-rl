import argparse
from hashlib import sha256
import json
from pathlib import Path

import numpy as np
from stable_baselines3 import PPO
import torch

from common import ROOT, checkpoint_physics, write_schema


class Actor(torch.nn.Module):
    def __init__(self, policy):
        super().__init__()
        self.net = policy.mlp_extractor.policy_net
        self.head = policy.action_net

    def forward(self, obs):
        return torch.clamp(self.head(self.net(obs)), -1, 1)


def export(checkpoint, output, level="insane", delay=10, physics_validation=None):
    checkpoint, output = Path(checkpoint), Path(output)
    checkpoint_path = checkpoint if checkpoint.suffix == ".zip" else checkpoint.with_suffix(".zip")
    provenance = checkpoint_physics(checkpoint_path, physics_validation)
    model = PPO.load(checkpoint, device="cpu")
    schema_path = write_schema()
    schema = json.loads(schema_path.read_text())
    output.mkdir(parents=True, exist_ok=True)
    actor = Actor(model.policy).eval()
    blocks = [layer for layer in actor.net if isinstance(layer, torch.nn.Linear)] + [actor.head]
    if [(layer.in_features, layer.out_features) for layer in blocks] != [(52, 64), (64, 64), (64, 2)]:
        raise ValueError("Actor must be 52 -> 64 -> 64 -> 2")
    weights = np.concatenate([tensor.detach().cpu().numpy().ravel() for layer in blocks for tensor in [layer.weight, layer.bias]]).astype("<f4")
    assert weights.size == 7682 and np.isfinite(weights).all()
    binary = weights.tobytes()
    (output / "actor.bin").write_bytes(binary)
    metadata = {"schema_version": 1, "dims": [52, 64, 64, 2], "activations": ["tanh", "tanh", "clip"],
                "matrix_order": "row-major", "dtype": "little-endian-float32", "parameters": 7682,
                "physics_hash": schema["physics_hash"], "schema_hash": sha256(schema_path.read_bytes()).hexdigest(),
                "training_physics_hash": provenance["physics_hash"], "physics_validation": physics_validation,
                "physics_hz": 120, "action_ticks": 4, "weights_sha256": sha256(binary).hexdigest(),
                "checkpoint_sha256": sha256(checkpoint_path.read_bytes()).hexdigest(), "trained_transitions": model.num_timesteps,
                "difficulty": level, "delay_ticks": delay, "normalization": schema["normalization"],
                "quality": "candidate; see validation/difficulty.json"}
    metadata["training_provenance"] = {key: provenance.get(key) for key in ["seed", "ppo", "curriculum", "warm_start", "resume"]}
    (output / "actor.json").write_text(json.dumps(metadata, indent=2) + "\n")
    torch.onnx.export(actor, torch.zeros(1, 52), output / "actor.onnx", input_names=["observation"],
                      output_names=["action"], dynamic_axes={"observation": {0: "batch"}, "action": {0: "batch"}},
                      opset_version=17, dynamo=False)
    assert len(binary) + (output / "actor.json").stat().st_size < 50 * 1024
    return metadata


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--level", default="insane")
    parser.add_argument("--delay", type=int, default=10)
    parser.add_argument("--physics-validation", help="Passed tournament for this exact checkpoint after a rule-only correction")
    args = parser.parse_args()
    print(json.dumps(export(args.checkpoint, args.output, args.level, args.delay, args.physics_validation), indent=2))
