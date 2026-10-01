"""Accepted rule migration cannot authorize another checkpoint or a failed gate."""
import json
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "training"))
from common import ROOT, checkpoint_physics

checkpoint = ROOT / "training/checkpoints/insane/final.zip"
validation = ROOT / "validation/difficulty.json"
checkpoint_physics(checkpoint, validation)
with tempfile.TemporaryDirectory(dir=ROOT / "training/runs") as directory:
    directory = Path(directory)
    (directory / "config.json").write_bytes((checkpoint.parent / "config.json").read_bytes())
    other = directory / "final.zip"
    other.write_bytes(b"not the evaluated checkpoint")
    for altered in [False, True]:
        report = json.loads(validation.read_text())
        if altered:
            report["qualified"] = False
        path = directory / "validation.json"
        path.write_text(json.dumps(report))
        try:
            checkpoint_physics(checkpoint if altered else other, path)
        except ValueError:
            pass
        else:
            raise AssertionError("Physics guard accepted a failed gate or different checkpoint")
print(json.dumps({"check": "checkpoint_physics", "failed_gate_and_wrong_checkpoint_rejected": True}))
