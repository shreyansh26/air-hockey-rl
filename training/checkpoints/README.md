# Retained checkpoints

The four level directories contain the selected SB3 PPO checkpoint, its actual
configuration/report, Python/NumPy/Torch RNG, Godot RNG, and frozen actor pool.
Pool paths are portable `res://training/checkpoints/...` paths. `bootstrap/`
and `quality/` retain the common demonstration and PPO foundations.

These are training artifacts, including critics and optimizer state. Production
exports exclude this entire directory. Runtime weights and portable ONNX
companions live in `models/`; selected hashes live in `models/manifest.json`.

Resume into a new output directory and raise the total budget above the saved
4,030,464 decisions:

```sh
uv run --project training python training/train.py --config training/checkpoints/insane/config.json --resume training/checkpoints/insane/final.zip --transitions 6000000 --output training/runs/insane-next
```

Resume restores optimizer and RNG and starts fresh rallies. `--warm-start`
copies actor/critic weights into fresh optimizer/exploration state instead.
Checkpoint configurations retain the original run locations as provenance;
use `--output` to choose where new artifacts are written.
