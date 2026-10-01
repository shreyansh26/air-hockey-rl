from hashlib import sha256
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVEL_DELAYS = {"easy": 30, "medium": 22, "hard": 14, "insane": 10}
PHYSICS_FILES = ["resources/physics.tres", "scripts/physics_config.gd", "scripts/arena.gd",
                 "scripts/paddle.gd", "scripts/puck.gd"]


def physics_hash():
    physics_settings = (ROOT / "project.godot").read_text().split("[physics]\n", 1)[1].split("\n[", 1)[0]
    data = "".join(f"{name}\n{(ROOT / name).read_text()}\n" for name in PHYSICS_FILES)
    return sha256((data + physics_settings).encode()).hexdigest()


def write_schema():
    schema = {"schema_version": 1, "engine": "4.5.1.stable", "physics_backend": "GodotPhysics2D",
              "physics_hash": physics_hash(), "physics_hz": 120, "action_ticks": 4,
              "features": 52, "history": {"samples": 4, "interval_ticks": 4, "order": "oldest-to-newest", "time_bound_ticks": 60},
              "sample_order": ["puck.x", "puck.y", "puck.vx", "puck.vy", "self.x", "self.y", "self.vx", "self.vy", "opponent.x", "opponent.y", "opponent.vx", "opponent.vy"],
              "tail_order": ["previous_action.x", "previous_action.y", "configured_delay", "latest_sample_age"],
              "normalization": {"position": "(x/600*2-1,y/1000*2-1)", "puck_velocity": 2300, "paddle_velocity": 1050, "position_clip": 1.1},
              "canonical_frame": "controlled paddle at bottom; top rotates positions and velocities 180 degrees",
              "action": "clip components [-1,1]; cap vector length 1 in shared motor; invert top command"}
    path = ROOT / "models/schema.json"
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(schema, indent=2) + "\n")
    return path
