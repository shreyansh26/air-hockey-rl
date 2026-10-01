# Glide — air hockey

A portrait Godot air-hockey game for the web and native Android. First to seven,
finger-follow touch or keyboard input, pause/rematch, three table finishes, independent puck
and paddle colors, local settings, offline assets, and small local PPO actors.

Version 0.1.1 maximizes the table with round pieces and places scores on the
board. The app uses immersive edge-to-edge display with no header or instruction
footer. Tall phones keep space above and below the proportional court. Paddles
remain controllable while the centered puck waits for a serve:
0.7 seconds on a new match, then a 0.55-second goal fade and 0.45-second re-serve.
Opening serves choose either player randomly; later serves go to the player
who conceded. Customization shows live previews and color/finish swatches.
Sound starts off and can be enabled in Settings or Pause. Existing installs
are muted once when upgrading; subsequent explicit choices are remembered.

Implementation/evidence: [validation/STATUS.md](validation/STATUS.md). Model
labels are not skill certificates: measured quality gates are recorded there.
The original bots failed their quality gates. The new actor bundle and the
reward, rollout, and trajectory analysis are in [docs/bot-quality.md](docs/bot-quality.md).

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
tools/godot --headless --path . --script checks/goal_flow_check.gd
tools/godot --headless --path . --script checks/touch_serve_check.gd
tools/godot --headless --path . --script checks/layout_check.gd
tools/godot --headless --path . --script checks/cosmetics_settings_check.gd
tools/godot --headless --path . --script checks/launch_check.gd
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
uv run --project training python training/bootstrap.py --output training/runs/bootstrap
uv run --project training python training/train.py --config training/configs/quality.json --warm-start training/runs/bootstrap/final.zip
uv run --project training python training/train.py --config training/configs/strategic.json --warm-start training/runs/quality/final.zip --seed 43 --delay 10 --output training/runs/strategic-43
uv run --project training python training/train.py --config training/configs/smoke.json
uv run --project training python training/train.py --config training/configs/pilot.json
uv run --project training python training/train.py --config training/configs/full.json --resume training/runs/pilot/final.zip
uv run --project training python training/export_policy.py --checkpoint training/runs/full/final.zip --output models/insane --level insane --delay 10
```

Selected SB3 checkpoints, RNG, and frozen opponents are retained in
[training/checkpoints/](training/checkpoints/README.md), so a fresh clone can
evaluate the shipped actors and resume training. The bootstrap teacher is
confined to training; gameplay always uses the selected neural actor.

The selected checkpoints retain the original training physics hash. Their
exact weights passed a fresh full tournament after the angled-goal correction.
Re-export them with the explicit compatibility report:

```sh
uv run --project training python training/export_policy.py --checkpoint training/checkpoints/insane/final.zip --output models/insane --level insane --delay 10 --physics-validation validation/difficulty.json
uv run --project training python checks/checkpoint_physics_check.py
```

Resume instructions in the checkpoint directory use the same report. New
training runs record the corrected Arena hash. Collision geometry, masses,
speeds, damping, motor controls and observation encoding did not change.

```sh
uv run --project training python training/parity.py
uv run --project training python training/quality_probe.py --checkpoint training/checkpoints/insane/final.zip --processes 4 --trace --output validation/quality-probe.json
uv run --project training python training/evaluate.py --matches 400 --processes 32 --arenas 8 --max-decisions 27000 --baselines intercept puck_chase
```

Parity generates ignored real-rollout fixtures for QA exports. Quality probes
use fixed per-world quotas and seed each task independently. Tournaments use
both sides, real first-to-seven outcomes, and explicit censoring; a long match
is never converted into a win. Gameplay and nominal evaluation share serves
and launch history. Evaluation durations exclude frozen presentation time.

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
tools/android-project.sh
tools/godot --headless --path . --export-release Web builds/web/index.html
tools/godot --headless --path . --export-debug Android builds/android/air-hockey-debug.apk
tools/godot --headless --path . --export-debug AndroidAAB builds/android/air-hockey-debug.aab
tools/godot --headless --path . --export-release TrainingLinux builds/training/air-hockey.x86_64
uv run --project training python checks/build_check.py
uv run --project training python -m http.server 8765 --bind 127.0.0.1 --directory builds/web
```

Open <http://127.0.0.1:8765/index.html>. The root route redirects to this cached
entry point. Python's server sends `.wasm` as `application/wasm`.
Production hosting needs HTTPS for PWA storage. Single-threaded WebGL 2 export
does not require isolation headers. Let the service worker finish caching before
going offline; after the first registration, reload once online to populate the
large WASM/PCK cache before checking offline startup. Browser eviction/private
storage can prevent persistent caching.
After a local rebuild, close the old game tab and reopen it so the waiting
service-worker version can activate. Keep the full export together.
Android bundles all assets and needs no network permission.

In Godot Editor Settings set the Android SDK and Java SDK (Android Studio's JBR
works on the tested host). Debug signing uses the engine's local debug key;
private keys are ignored. The Android Gradle template belongs in `android/build`
and is generated from the matching `android_source.zip`. Open that folder in
Android Studio. AAB export requires the Gradle build and user-owned release
signing credentials; the included AAB preset can also produce a debug-signed
bundle. No store publication is part of this project.

For an actual native regression on a **disposable** AVD, first generate parity
fixtures, then build/install the QA APK. The harness clears only this game's
test data and disables networking in that named AVD:

```sh
tools/godot --headless --path . --export-debug AndroidQA builds/android/air-hockey-qa.apk
adb -s emulator-5554 install -r builds/android/air-hockey-qa.apk
uv run --project training python checks/android_e2e.py --serial emulator-5554 --port 5037 --apk builds/android/air-hockey-qa.apk --soak
adb -s emulator-5554 shell run-as com.shreyansh26.glide cat files/qa-soak.json
```

The command starts a 20-minute **active** soak after the four-level regression;
it does not wait for completion. Verify `soak_complete` and at least 1200 active
seconds in the final report. WebQA provides the same `physics`, `parity`, and
`soak` commands through its visible QA input. Production builds exclude QA.

WebQA also accepts `{"type":"telemetry","enabled":false}` to stop periodic
publishing, `{"type":"snapshot"}` for one sample, and
`{"type":"silence","seconds":45}` to pause all QA processing temporarily.
These diagnostic controls leave the game running. Memory/performance limits
and metric definitions are recorded in [the validation report](validation/STATUS.md).

## Layout

`scenes/` contains the main, independent arena and shared paddle. `scripts/`
contains bodies, controls, drawing, state history and tiny actor inference.
`resources/physics.tres` holds frozen physical constants. Gameplay renders an
unscaled isolated `World2D` through a viewport texture; resizing the display
never rescales the physics. Presentation uniformly fits the texture to the
screen with the same invertible mapping for touch; circles remain round and
body artwork stays aligned with its collider projection on every device.
The unchanged logical dimensions, body motors and trained weights require no
retraining for this display change. `models/` holds deployment assets. `training/`
contains the headless bridge and Python tools; `checks/` holds runnable
regressions. Production export presets exclude training and checks.

All cosmetics affect drawing only. A damaged settings file recovers to defaults;
unavailable browser storage leaves the game playable for the current session.
The game pauses on background/focus loss and requires explicit resume. Extra
touch IDs are ignored; release/cancel/pause clears the shared motor command.

The original Glide boot artwork replaces the engine splash. A silent,
nonblocking half-second intro fades into the ready menu; Reduced effects skips
it. To regenerate its PNG from the SVG, run the launch check with `-- --regenerate`.

Original assets and upstream adaptations are documented in [THIRD_PARTY.md](THIRD_PARTY.md).
