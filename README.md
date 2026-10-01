# Glide — air hockey

A portrait Godot air-hockey game for the web and native Android. First to seven,
drag or keyboard input, pause/rematch, three table finishes, independent puck
and paddle colors, local settings, offline assets, and small local PPO actors.

Implementation/evidence: [validation/STATUS.md](validation/STATUS.md). Model
labels are not skill certificates: measured quality gates are recorded there.

## Run

Use **Godot 4.5.1 stable**, standard editor, matching export templates,
Compatibility renderer. On macOS the official engine/templates bootstrap is:

```sh
tools/setup.sh
tools/godot --path .
```

`tools/godot` points to the task-local engine. On another OS install the same
official engine and put `godot` on PATH. Python runs only in `training/.venv`:

```sh
uv sync --project training --frozen
tools/godot --headless --path . --script checks/physics_check.gd
tools/godot --headless --path . --script checks/observation_check.gd
uv run --project training python training/check.py
```

Physics checks exercise real Godot bodies, including 100 seeded fast trajectories,
goals, posts, strikes, corners, boundaries and resets. Contact penetration below
two logical units for one tick is allowed; passing through the 40-unit rail is not.
The bridge check asserts actual four-tick travel, pause while Python waits,
isolated worlds, terminal/reset separation, timeout metadata, PPO updates and
optimizer-preserving resume; it also measures batches of 16/32/64 arenas.

## Train and export

```sh
uv run --project training python training/train.py --config training/configs/smoke.json
uv run --project training python training/train.py --config training/configs/pilot.json
uv run --project training python training/train.py --config training/configs/full.json --resume training/runs/pilot/final.zip
uv run --project training python training/export_policy.py --checkpoint training/runs/full/final.zip --output models/insane --level insane --delay 10
```

Use `--seed`, `--delay`, and `--output` for independent seeds and profile runs.
Delays are Easy=30, Medium=22, Hard=14 and Insane=10 ticks. Train each chosen
checkpoint under its shipped delay. Configurations state aggregate transitions,
curriculum, rewards, architecture and every PPO hyperparameter. `GODOT` overrides
the engine launcher for a Linux checkout. The shared Arena is the environment;
Python contains no substitute physics or PPO implementation.

Checkpoints retain SB3's critic/optimizer and exploration variance. Clean
interruption saves `final.zip`, Python/NumPy/Torch RNG, config, timings and a
frozen-opponent pool. Resume preserves optimizer state; it begins fresh rallies.
Opponent checkpoints are fixed within episodes, never hot-swapped mid-rally.

Runtime actors are little-endian row-major FP32 `52 → 64 → 64 → 2`, tanh hidden
layers, and clipped means. Only the selected actor loads during gameplay. The
ONNX companion accepts the same **already normalized 52-vector** described in
`models/schema.json`; it includes output clipping. Vector-length capping belongs
to the shared motor. Physics/source, schema, checkpoint and weight hashes travel
with the model bundle. Incompatible/missing models stop Play with a visible error.

## Build and serve

```sh
mkdir -p builds/web builds/android builds/training
tools/godot --headless --path . --export-release Web builds/web/index.html
tools/godot --headless --path . --export-debug Android builds/android/air-hockey-debug.apk
tools/godot --headless --path . --export-release TrainingLinux builds/training/air-hockey.x86_64
uv run --project training python -m http.server 8765 --bind 127.0.0.1 --directory builds/web
```

Open <http://127.0.0.1:8765>. Python's server sends `.wasm` as `application/wasm`.
Production hosting needs HTTPS for PWA storage. Single-threaded WebGL 2 export
does not require isolation headers. Let the service worker finish caching before
going offline; browser eviction/private storage can prevent persistent caching.
Android bundles all assets and needs no network permission.

In Godot Editor Settings set the Android SDK and Java SDK (Android Studio's JBR
works on the tested host). Debug signing uses the engine's local debug key;
private keys are ignored. The Android Gradle template belongs in `android/build`
and is generated from the matching `android_source.zip`. Open that folder in
Android Studio. AAB export requires the Gradle build and user-owned release
signing credentials; no store publication is part of this project.

## Layout

`scenes/` contains the main, independent arena and shared paddle. `scripts/`
contains bodies, controls, drawing, state history and tiny actor inference.
`resources/physics.tres` holds frozen physical constants. Gameplay renders an
unscaled isolated `World2D` through a viewport texture; resizing the display
never rescales the physics. `models/` holds deployment assets. `training/`
contains the headless bridge and Python tools; `checks/` holds runnable
regressions. Production export presets exclude training and checks.

All cosmetics affect drawing only. A damaged settings file recovers to defaults;
unavailable browser storage leaves the game playable for the current session.
The game pauses on background/focus loss and requires explicit resume. Extra
touch IDs are ignored; release/cancel/pause clears the shared motor command.

Original assets and upstream adaptations are documented in [THIRD_PARTY.md](THIRD_PARTY.md).
