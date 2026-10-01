# Godot air hockey with Python/Stable Baselines3 RL training

Date: 2026-10-01. Status: ready for implementation. This document plans the work; it does not claim that the game, training, exports, or device tests have been implemented.

## Product contract

Build a polished, single-player air-hockey game with an RL opponent, playable in browsers and as a native Android app. Use Godot for both platforms and for the training simulation.

Confirmed requirements:

- Godot is the chosen game engine.
- Model training is Python-based and uses Stable Baselines3 PPO with PyTorch. Godot runs the environment; it does not train the neural network.
- Easy, Medium, Hard, and Insane all use trained RL policies, with distinct skills and fair movement.
- The opponent reads the puck's state and slides its paddle continuously to intercept and strike it.
- Physics must handle fast movement, collisions, rebounds, goals, and resets reliably.
- Models must be small, exportable, and execute locally on phones.
- The presentation is top-down 2D with shaded objects that appear raised above the table.
- Players can customize the table, puck, and paddles.
- Validate the exported web build in browsers and the actual Android app through Android Studio and a virtual device.
- The 8×H100 machine is available if useful for training; access and current availability must be verified at execution time.

Defaults adopted where the user has not specified details:

- Portrait table, human at the bottom, computer at the top. Desktop uses the same table with surrounding space for menus.
- Responsive arcade physics inspired by real air hockey, rather than a physical air-flow or 3D simulation.
- First to 7 points; no win-by-two rule. Countdown, pause, rematch, and automatic re-serve after a goal.
- Touch/mouse drag control, keyboard alternative on desktop, and optional touch offset adjustment.
- All difficulties and cosmetics available immediately. No accounts, ads, purchases, campaign, multiplayer, or live inference server in this release.
- Android works offline from the first launch. Web works offline after its PWA assets have been cached successfully.
- Cosmetics change appearance only; table dimensions, object radii, friction, mass, and movement limits stay fixed.

The reference screenshot is visual inspiration: blue perforated surface, metallic rim, raised paddles, and puck shadows. Create original artwork and branding; do not reuse the screenshot's logo or other artwork.

## Architecture and execution flow

Use a pinned stable Godot 4 release, standard GDScript, the Compatibility renderer, and Godot's built-in 2D physics. Select the exact engine patch and matching export templates during the first implementation task and record them. Use the same physics backend and engine version in training, native Android, and web.

Godot's web export requires WebAssembly and WebGL 2. Godot 4 currently does not export C# projects to web, so do not build the game around C# or a .NET inference dependency. Start with the single-threaded web export to reduce hosting requirements. [Godot web export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)

```text
Touch / mouse / keyboard ──> desired paddle velocity ─┐
                                                   ├─> shared paddle motor
World state ─> observation history ─> RL actor ──────┘        │
                                                            v
                                                   Godot 2D physics
                                                            │
                                         ┌──────────────────┴─────────────┐
                                         v                                v
                                  next world state                goals / match state
                                         │                                │
                                         └───────────────┬────────────────┘
                                                         v
                                             visuals, sound, and HUD

Training: the same Arena scene, headless
  state + reward ─> local bridge ─> Python SB3 VecEnv ─> SB3 PPO
  action        <─ local bridge <─ Python SB3 VecEnv <─ PyTorch actor

Deployment: Python checkpoint ─> actor export ─> bundled GDScript inference
```

There is no camera, image recognition, or discrete board grid. Coordinates and velocities already exist in the simulation. The model chooses a movement command; it never teleports a paddle, changes puck velocity directly, or selects a guaranteed hit.

The gameplay backend is local game logic. The ML backend is an offline training tool. No always-on application backend is required for the chosen product scope.

### Suggested locations

Keep one Godot project at the repository root. These are proposed implementation paths, not existing files. Combine small scripts where that makes ownership clearer; do not introduce an ECS or plugin architecture.

| Location | Responsibility |
|---|---|
| `project.godot`, `export_presets.cfg` | Engine settings; web, Android, and training exports |
| `scenes/arena.tscn`, `scripts/arena.gd` | Shared table, puck, walls, goal detection, and rally reset |
| `scenes/paddle.tscn`, `scripts/paddle.gd` | The same physical paddle and motor for both sides |
| `scenes/main.tscn`, `scripts/main.gd` | Match state, player input, menus, HUD, pause, and settings |
| `scripts/observation.gd`, `scripts/policy.gd` | State encoding, delayed history, tiny actor execution |
| `resources/physics.tres`, `resources/difficulties.tres` | Authoritative physics constants and calibrated profiles |
| `resources/skins/`, `assets/` | Cosmetic definitions, original textures, audio, fonts, icons |
| `training/training.tscn`, `training/training_sync.gd` | Headless batch of shared arenas; training-only communication |
| `training/pyproject.toml`, `training/uv.lock` | Task-local Python dependencies |
| `training/env.py`, `train.py`, `evaluate.py`, `export_policy.py` | Godot/SB3 VecEnv adapter, PPO configuration, evaluation, actor export |
| `training/patches/` | Small reproducible Godot bridge/transport adaptations, only if required |
| `models/` | Release actors, manifests, and difficulty mapping |
| `checks/`, `training/check.py` | Small runnable regression checks and export parity checks |
| `builds/`, `training/runs/`, `validation/` | Ignored build/run output; retained validation summaries |

Use explicit scene references. An arena must work without the menu, audio, or training bridge. Training spawns the actual Arena scene, rather than reconstructing it in Python.

## Physics and controls contract

### Coordinates and time

- Store simulation positions in a fixed table coordinate system. Screen resolution and UI scaling must not resize colliders or alter physics.
- Start with a logical table around 600×1000 units. Tune actual dimensions and radii during playtesting, then freeze the physics resource before long training.
- Start at 120 physics ticks/s, with AI decisions at 30 Hz: exactly four physics ticks per policy action. These values are design defaults, not measured performance claims.
- Apply movement in physics integration. Render with Godot's physics interpolation; UI and decorative animations may update per rendered frame.
- Keep `Engine.time_scale = 1`. Every training tick must represent the same 1/120 second as gameplay.
- Changing the tick rate or policy interval after training changes the environment; rerun validation and retrain if necessary.

Godot distinguishes physics tick frequency, catch-up limits, and time scale. Increasing time scale alone can increase the effective integration step and reduce accuracy. [Engine timing documentation](https://docs.godotengine.org/en/stable/classes/class_engine.html)

### Bodies and boundaries

- Puck: circular `RigidBody2D`, zero gravity, explicit low damping, bounded speed, tuned bounce, and shape-based continuous collision detection.
- Paddles: circular, rotation-locked `RigidBody2D` bodies with finite mass and the same motor code. In `_integrate_forces`, move velocity toward the requested velocity with a bounded acceleration; preserve the physics solver's collision response. Do not assign transforms on every input event.
- Rails and goalposts: fixed colliders with thickness. Use rounded corner geometry to avoid trapping the puck in sharp seams.
- Add paddle-only boundary colliders for each half and behind each goal mouth. They must not block the puck's path to a goal. Clamp input targets as well, so the motor does not continually drive into forbidden space.
- Avoid an infinite-mass kinematic paddle unless the prototype demonstrates a clear reason to change body type. A speed/acceleration-limited finite-mass motor is the baseline.
- Explicitly configure damping mode and friction so project defaults do not silently change behavior.
- Lock puck rotation for the first version; shading provides depth. Add physical spin only if playtesting demands it, and then extend the observation schema and retrain.

Godot supports shape-based CCD and custom force integration while retaining collision response. CCD still needs actual high-speed regression tests; enabling the flag is not proof of correctness. [RigidBody2D documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)

### Paddle motor and player input

- Both controllers request a normalized 2D desired velocity. Clamp components to [-1, 1] and cap vector length to 1 before applying the shared speed limit.
- Touch starts in the human's playable half. Preserve the initial finger-to-paddle offset, so grabbing away from the paddle does not snap it to the finger.
- Convert the drag target into a desired velocity using a simple bounded position servo. The actual paddle follows through the shared motor, with collision-aware movement.
- Track one active touch ID; ignore extra fingers for paddle motion. Clear input on release, cancellation, focus loss, and pause.
- Mouse drag follows the same path. Keyboard movement produces the same motor command.
- Speed, acceleration, mass, radius, and movement region are identical for the human and every bot level. The bot observes actual opponent motion, never the user's future touch target.
- Keep a small input-offset setting for visibility, and prevent browser scrolling or text selection while interacting with the game surface.

### Goals, serves, and failure recovery

- Count a point once the puck completely clears the goal plane through the legal mouth. Use the prior and current physics positions to detect fast crossings; do not depend solely on an `Area2D` overlap event.
- Treat a post hit or a crossing outside the legal aperture as a collision, not a goal. Validate radius clearance and swept crossing position.
- Match transitions: menu → countdown → rally → goal presentation → serve → rally, or results when a player reaches 7. Pause stores the previous state.
- A point immediately disables further scoring for that rally. Reset velocities, motor commands, timers, histories, contact bookkeeping, and interpolation when serving again.
- Alternate the opening serve side between matches; after a goal, serve to the player who conceded. Use a predictable short countdown and a gentle opening puck motion so matches cannot stall at the start.
- If the puck remains nearly motionless and untouched for a configurable interval, re-serve without awarding a point. Log this event during training/evaluation. Do not use an invisible mid-rally speed boost.
- Cap extreme solver-generated velocities in shared integration code. Reject non-finite state in checks; recover a broken rally safely in production without awarding arbitrary points.

Godot requires resetting interpolation on intentional teleports such as a re-serve. [Physics interpolation documentation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html)

## RL contract

### Observation and action

Use a small fully connected actor, not a vision model. Define the exact schema in one manifest and implement it once in Godot, used by both training and shipped inference.

Baseline input: 52 numbers.

- Four state samples, oldest to newest, at 30 Hz. Each contains puck `(x, y, vx, vy)`, bot paddle `(x, y, vx, vy)`, and opponent paddle `(x, y, vx, vy)`: 4×12 = 48 values.
- Previous bot command `(ax, ay)`: 2 values.
- Configured observation delay and age of the latest sample: 2 values, normalized by an explicit time bound.

Normalize positions using table dimensions and velocities using shared speed bounds. Use a canonical frame with the controlled paddle always on the bottom: rotate the top player's positions and velocities by 180 degrees and invert the output consistently. Do not treat velocity as a point when transforming coordinates.

Maintain the observation ring buffer at physics ticks, and select delayed samples at decision boundaries. The configured delay affects the whole observed world; there must be no separate current-position intercept heuristic that bypasses it. Reinitialize the history after every serve or reset so the previous rally cannot leak into the next.

Output: two continuous desired-velocity components. Use the PPO policy's deterministic mean during gameplay, with the exact same clipping and motor mapping as training.

### Network and export

- Start with `52 → 64 → 64 → 2`, tanh hidden activations, linear output followed by action clipping. Actor size: `(52+1)×64 + (64+1)×64 + (64+1)×2 = 7,682` parameters.
- Raw FP32 actor weights occupy 30,728 bytes, approximately 30 KiB, before metadata. This is a parameter calculation, not an observed artifact size or timing benchmark.
- PPO's critic and exploration variance are training-only. Do not ship the optimizer, critic, Python, PyTorch, or training sockets.
- Export each selected actor to a small JSON manifest plus little-endian FP32 binary weights. Record dimensions, activations, row-major matrix order, schema version, normalization, action interval, physics hash, checkpoint hash, difficulty profile, and checksum.
- Also export a standard ONNX actor as a portable companion artifact. Include preprocessing and action clipping in its contract. Validate it against Python and GDScript.
- Production runs the fixed three-layer MLP in a short GDScript script with reusable packed arrays. It is not a general ONNX interpreter. Bundle all four small actors, but load/evaluate only the chosen level during a match.
- Target less than 50 KiB per actor including its runtime manifest; target less than 250 KiB total for the four runtime policies and profiles. Report the ONNX companion size separately.
- Do not introduce quantization, an RNN, or a native inference extension unless measurements show the baseline is insufficient. If network capacity is insufficient, compare a 128-wide MLP before changing the runtime architecture.
- Validate expected array lengths, supported versions, checksums, finite weights, and finite outputs at load. A bad model produces an actionable error; the release must not silently substitute a scripted opponent.

The existing Godot RL Agents ONNX playback instructions use the .NET editor; that integration is not the browser deployment path here. [Godot RL Agents export instructions](https://github.com/edbeeching/godot_rl_agents#exporting-and-loading-your-trained-agent-in-onnx-format)

### Trainer and simulation reuse

Use Stable Baselines3 (SB3) PPO in Python with PyTorch and Gymnasium-compatible spaces. Pin compatible stable SB3, PyTorch, Gymnasium, and Godot RL Agents versions/revisions in the task-local uv environment. Use SB3's existing policy, optimizer, rollout buffer, callbacks, and PPO update; do not write a custom learner or patch SB3's PPO implementation.

Configure the standard `MlpPolicy` with separate actor and critic branches of two 64-wide layers and tanh activations. The deployed actor remains `52 → 64 → 64 → 2`; the critic stays in Python. Start with CPU training and deterministic mean actions for evaluation. SB3 supports continuous Box actions and recommends CPU-first PPO for small MLP policies. [SB3 PPO documentation](https://stable-baselines3.readthedocs.io/en/master/modules/ppo.html), [policy configuration](https://stable-baselines3.readthedocs.io/en/master/guide/custom_policy.html)

Use these policy settings in the training entry point; they specify architecture, not optimized hyperparameters:

```python
policy_kwargs = {
    "net_arch": {"pi": [64, 64], "vf": [64, 64]},
    "activation_fn": torch.nn.Tanh,
}
model = PPO("MlpPolicy", vec_env, policy_kwargs=policy_kwargs, device="cpu")
```

Reuse Godot RL Agents' Python client and SB3 integration behind a thin project adapter in `training/env.py`. Keep its source revision and any transport adaptations recorded. It already provides the connection between Godot and Python training; audit its timestep/reset behavior instead of assuming the stock wrapper meets this game's contract. [Godot RL Agents](https://github.com/edbeeching/godot_rl_agents)

Expose a batched SB3 VecEnv with one learner per independent arena:

- `num_envs = N`; N means different games, not both competing paddles from one game.
- Per-environment observation space: float32 Box with shape `(52,)` and documented feature bounds. Per-environment action space: float32 Box `[-1, 1]` with shape `(2,)`.
- Batch observations have shape `(N, 52)`, actions `(N, 2)`, and rewards/dones `(N,)`; infos is a list of N dictionaries.
- If the reused bridge provides `{"obs": vector}`, use SB3's observation-extraction wrapper to expose the flat vector to `MlpPolicy`. Do not add a custom network just to unwrap one dictionary key.
- `reset()` returns observations; keep reset metadata in `reset_infos`. Implement the expected VecEnv step and attribute/method interfaces used by the selected SB3 wrappers/callbacks.
- `step()` returns `(observations, rewards, dones, infos)`, where done is termination or truncation. At an episode boundary, return the reset observation and separately preserve the final observation in `info["terminal_observation"]`. Set `info["TimeLimit.truncated"]` only for an artificial timeout without a simultaneous true termination.
- SB3 handles timeout value bootstrapping when the adapter supplies the correct metadata. Do not manually add a value bootstrap to rewards; that would duplicate the trainer's correction.
- One batched exchange advances the N tables; do not launch a process or open a socket per decision. Close every owned process/socket on exit.

This VecEnv API differs from Gymnasium's five-value step API. Keep that conversion at the project adapter boundary. [SB3 VecEnv contract](https://stable-baselines3.readthedocs.io/en/master/guide/vec_envs.html)

Use fixed analytical normalization for the bounded state. Do not add VecNormalize or a second frame stack on top of the existing 52-feature Godot encoder by default. If running statistics become necessary, freeze and export them explicitly.

During training, let SB3 sample and track the continuous action distribution. The engine receives bounded commands, applies the shared vector-length cap, and then the paddle motor. During evaluation/deployment use the deterministic mean with the same clipping/motor mapping. Export the actor branch and action head, excluding value-network weights and exploration variance; compare outputs with `model.predict(observation, deterministic=True)`. Include any preprocessing and action clipping in the ONNX/runtime contract. [SB3 export documentation](https://stable-baselines3.readthedocs.io/en/master/guide/export.html)

Implement a narrow training-only GDScript bridge based on the Godot RL Agents Sync/controller source, retaining its license and recording adaptations:

- Remove ONNX/.NET type references and inference/demo features from the dependency path. The project must parse in the standard Godot editor.
- Keep 120 Hz physics and time scale 1 instead of the upstream hard-coded 60 Hz base.
- Execute exactly four real engine physics ticks per accepted action. Stop while waiting for the next action; Python update time must not produce uncontrolled simulation steps.
- Run headless without wall-clock synchronization using correctly tokenized arguments `--fixed-fps`, `120`. Verify integration delta and step count; do not manually call `_physics_process` to imitate physics.
- Return separate termination/truncation flags and the final state to the Python adapter. Freeze a terminal arena immediately so a goal in the middle of an action repeat preserves its final observation.
- Reset only finished arenas. Clear their histories, timers, commands, and contact bookkeeping, then expose the reset state independently from the final state.
- Keep learner and opponent state separate. The opponent is an independently controlled frozen actor or development baseline.
- Bind to loopback, use finite timeouts, validate message lengths/shapes/numbers, and close child processes on failure.

The upstream transport/wrapper inspected during planning has a 60 Hz base, native ONNX references, a combined fixed-fps launcher argument, and incomplete terminal/truncation handling. Recheck the pinned revision and make the narrow bridge/adapter fixes required here. Keep changes at those integration boundaries and use stock SB3 PPO. [Sync source](https://github.com/edbeeching/godot_rl_agents_plugin/blob/main/addons/godot_rl_agents/sync.gd), [Python transport](https://github.com/edbeeching/godot_rl_agents/blob/main/godot_rl/core/godot_env.py), [upstream SB3 wrapper](https://github.com/edbeeching/godot_rl_agents/blob/main/godot_rl/wrappers/stable_baselines_wrapper.py)

First run 16 isolated arenas in one headless process; compare 32 and 64 after correctness passes. Each gets its own `World2D` via an isolated viewport with rendering disabled. Verify resets, collisions, signals, and random streams do not cross arenas. If one process saturates a core, compare a few independently batched headless processes using the bridge's existing multi-process support. Do not wrap an already-batched VecEnv in DummyVecEnv or SubprocVecEnv; those wrappers expect single-environment instances.

Godot supports headless fixed-FPS operation without real-time synchronization. Measure environment, transport, inference, and learner time separately before adding GPU or process parallelism. [Godot command-line documentation](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

### Curriculum, rewards, and opponents

RL generates transitions through simulated play; there is no required pre-existing labeled dataset. Save checkpoints, evaluation scenarios, representative replays, and configuration rather than every training frame.

1. Train controlled defensive drills: randomized incoming puck shots, including rebounds and post-adjacent trajectories.
2. Train offensive drills: varied reachable puck states, targets, and stationary/weak opposing defense.
3. Train full rallies against a mix of scripted training opponents: reactive chase, center defense, and a stronger trajectory-interception baseline.
4. Add self-play against a pool of frozen past checkpoints, retaining some scripted opponents to prevent a narrow shared strategy.
5. Fine-tune in the final shipped observation-delay profiles and verify complete matches, not only drills.

Use the same paddle motor and actual contacts in every drill. A curriculum changes resets and opponents, not the shipped collision law. Evaluate without drill assistance or training rewards.

Reward baseline: +1 for scoring, -1 for conceding, with small bounded shaping while the policy learns. If using progress shaping, use `gamma * Phi(next_state) - Phi(state)` with terminal potential zero and an explicit bound. A tiny smoothness cost can penalize repeated large command changes, but must not outweigh scoring. Any temporary hit reward is capped per rally and annealed away; inspect replays for touch farming, camping, intentional stalls, and excessive wall pushing. Compute event rewards once, rather than once per contacting physics tick.

Keep frozen opponents fixed for each rollout/episode; replace them only at documented boundaries. Do not change the opponent's weights during an episode. Reserve held-out seeds and opponent styles for evaluation. Randomize legal starting states, serve directions, and opponent behavior first; keep physical constants fixed for the initial training. Small physics variations may be added only after nominal physics works, with the nominal shipped configuration always included in evaluation.

Start with SB3 PPO settings appropriate for continuous control, the small MLP, fixed gamma, and explicit seeds. Record learning rate, n_steps, batch_size, n_epochs, gamma, gae_lambda, clip_range, ent_coef, and any deviation from stable-version defaults. Do not treat this plan's values as an optimized recipe. Use at least three independent seeds to assess whether a promising policy is repeatable.

Use SB3 checkpoint/evaluation callbacks and local TensorBoard/CSV artifacts, with hosted tracking and uploads disabled. Save/load through SB3's model API and preserve the separate opponent pool/configuration/RNG metadata. Handle clean interruption with a final checkpoint and environment close in a try/finally path; verify the run can resume without recreating the optimizer.

### Compute and run budgets

- Use a task-local uv environment under `training/`; pin dependencies and commit its lockfile. Do not install ML packages globally.
- Begin with a 50k-transition smoke run, then a 500k pilot. Inspect learning curves and replay behavior before extending a run to 5M transitions. These counts are aggregate learner decisions across arenas, not physics ticks or per-arena counts.
- Benchmark environment steps/s, bridge time, policy inference, PPO update time, CPU utilization, and memory separately. Report simulated seconds per wall-clock second and total transitions.
- Run local CPU simulation, actor/export checks, and SB3 smoke training. Start the pilot with `device="cpu"`; compare measured CPU training on the local machine and the remote host's available CPU resources before choosing the full-run location. No GPU is required for the shipped game or its end-to-end tests.
- Pin stable SB3/PyTorch/Gymnasium/Godot RL Agents dependencies in uv. Validate the adapter, one actual PPO update, checkpoint reload, and export parity. A successful install alone is not training readiness. Use compatible CPU wheels locally and CUDA wheels only for a measured remote GPU experiment.
- On the 8×H100 host, verify current SSH access, repository isolation, engine availability, CPU capacity, GPU availability, CUDA initialization, and device flags. Use a project-specific checkout and uv environment.
- Compare CPU against one H100 only after the pilot works. Keep GPU training only if it improves end-to-end throughput; available CPU cores may matter more than GPU count. Other GPUs can run independent seeds/configurations if justified; do not add multi-GPU gradient synchronization for this small model.
- If CUDA initialization fails, inspect the host's existing MPS configuration and use an isolated client pipe when appropriate. Do not restart a shared daemon or other users' work. Previous host notes are not proof of its current state.
- Checkpoint at regular intervals and on clean interruption. Preserve the optimizer, RNG/configuration state, and frozen-opponent pool for training resume.
- Stop and diagnose flat or pathological learning before spending another order of magnitude of transitions. A training timeout must leave a usable checkpoint and a clear report of unmet quality gates.

## Difficulty contract

Select four qualified actor checkpoints/profiles from the training lineage. They can share architecture and originate from the same run; four independent training jobs are not required. If an early checkpoint behaves erratically, train or fine-tune a purposeful weaker policy rather than accepting visibly random movement.

| Level | Intended behavior | Initial observation delay for calibration |
|---|---|---|
| Easy | Can return simple shots; leaves openings; limited rebound defense | 250 ms |
| Medium | Sustains rallies; covers direct shots; attacks open space | About 183 ms |
| Hard | Anticipates rebounds; places shots; recovers consistently | About 117 ms |
| Insane | Strongest validated policy; accurate interception and attack | About 83 ms |

The delays are initial, tick-aligned design values, not established human reaction measurements. Evaluate and tune them in playtests. All levels keep the same 30 Hz decision cadence and shared physical limits. Do not make difficulty by increasing puck speed, enlarging the bot paddle, allowing it across the center, reading future input, or randomly dropping actions each frame. The difficulty profile is fixed for the match.

Train with the profile delays used in deployment; adding latency only after training is a distribution shift. Checkpoint quality is determined by evaluation, not training age. Changing a cosmetic must never change a level's skill.

Proposed measurable release gates, to be calibrated during the pilot:

- A fixed panel of opponents, serve seeds, incoming shots, and both table sides produces a monotonic Easy < Medium < Hard < Insane ranking.
- Run at least 400 first-to-7 matches for each adjacent level pair, balanced by side and serve. Require the stronger level's estimated win rate above 55% and its 95% interval lower bound above 50%; increase match count if the result remains uncertain. Do not call four labels distinct merely because delays differ.
- Insane wins at least 80% of held-out matches against the predefined strong interception baseline. Treat this as a target to test, not a promise that PPO will achieve it.
- Report score difference, save rate on held-out shots, rally length, stalls, boundary violations, motor smoothness, and matchup win rates. Reward alone is not a skill metric.
- Playtest with beginner and experienced humans to confirm Easy is approachable and Insane is challenging. Scripted-opponent scores alone cannot establish the human experience.
- Publish the final checkpoint/profile mapping and evaluation report. If a gate fails, continue bounded training/tuning or report it explicitly; do not quietly ship a heuristic as an RL level.

## Presentation and customization

Build the table as real 2D gameplay with original layered artwork. Use highlights, bevels, contact shadows, and a restrained material shader to create depth. A 3D scene is not needed for the requested look.

- Table fills most of the portrait display; rails, goal mouths, center line, and scoring marks remain legible.
- Use a consistent light direction for the rim, puck, and paddles. Shadows must track objects and preserve their visible collision footprints.
- Give human and bot paddles distinct colors by default. Keep the puck easy to locate at maximum speed and against every allowed surface.
- Add brief speed-dependent puck trails, contact particles, impact audio scaled by collision intensity, a restrained goal effect, and optional haptics on Android.
- Avoid large screen shake or flashes that obscure tracking. Include reduced-effects, sound, and haptics toggles.
- Menus: Play, difficulty selector, Customize, Settings; in-match score and pause; results with Rematch and Menu. Do not add an unrelated tutorial overlay to every match.
- Offer at least three coherent table finishes, several puck colors/finishes, and separate human/bot paddle choices. Include live previews and a reset-to-default action.
- Keep skin assets separate from physics shapes. Use a small Skin resource to store tint, texture/material, and appearance choices; do not introduce a skin scripting system.
- Persist settings locally in `user://` using ConfigFile. Recover from a damaged settings file with defaults without losing the ability to play. For web, test browser persistence and explain session-only behavior when storage is unavailable.
- Fit small/tall phones and desktop windows without stretching the table. Respect safe areas and system bars. Under landscape or resizing, preserve aspect ratio rather than altering physics.
- Give menus visible keyboard focus, large touch targets, readable contrast, and color choices that preserve puck/paddle separation.
- Preload small audio samples. On web, enable audio through the user's Play gesture; account for browser audio restrictions.

Create one finished default theme early, then apply the same materials and layout rules to the other skins. Validate polish in motion, not only in a screenshot.

## Implementation milestones and acceptance gates

Each milestone produces a runnable increment. Tasks are intentionally ordered around uncertainty: shared physics, both exports, training integration, trained gameplay, then final polish and release validation.

### 1. Toolchain and cross-platform physics prototype

| Task | Files / output | Depends on | Acceptance / check |
|---|---|---|---|
| 1.1 Pin toolchain and create project | `project.godot`, `export_presets.cfg`, `.gitignore`, version note | None | Standard Godot editor imports project; exact engine/templates recorded; Compatibility renderer selected |
| 1.2 Build shared arena and paddle motor | Arena/Paddle scenes, physics resource | 1.1 | Human paddle moves smoothly; rails/posts rebound puck; goals and half boundaries behave correctly |
| 1.3 Add physics regression scenarios | `checks/physics_check.gd` | 1.2 | Headless assert-based check exits nonzero for tunneling, invalid goals, duplicate scores, illegal movement, or bad reset |
| 1.4 Export early web and Android builds | `builds/web/`, `builds/android/`; short evidence note | 1.2–1.3 | Actual exported game plays in browser and Android Studio AVD; touch coordinates and aspect ratio are correct |

Demo: a plain but responsive table with human input and a clearly labeled development-only scripted opponent. Do not present that opponent as the final RL bot. Gate: fast-shot/post/corner tests and both exports work before training investment.

### 2. State encoding, training bridge, and actor runtime

| Task | Files / output | Depends on | Acceptance / check |
|---|---|---|---|
| 2.1 Define observation/action manifest | `scripts/observation.gd`, schema fixture | 1.2 | Exactly 52 features; normalization, history delay, and top/bottom transforms pass known-state assertions |
| 2.2 Configure SB3 policy, export wrapper, and GDScript actor | `training/train.py`, `training/export_policy.py`, `scripts/policy.gd`, known weights | 2.1, 2.3 | Standard MlpPolicy has the specified architecture; deterministic mean parity; no production .NET dependency |
| 2.3 Set up pinned Python/SB3 environment | `training/pyproject.toml`, `uv.lock` | 1.1 | Compatible stable SB3/PyTorch/Gymnasium/client versions recorded; a standard Gymnasium Pendulum smoke run updates PPO and reloads its checkpoint |
| 2.4 Adapt Godot RL Agents transport and SB3 VecEnv | `training_sync.gd`, controller, `env.py`, training scene | 1.3, 2.1, 2.3 | Exact tick stepping, correct batch shapes/reset metadata, goal/timeout semantics, loopback bridge, child cleanup |
| 2.5 Validate vectorized simulation and Godot PPO update | Training checks and throughput report | 2.2, 2.4 | Independent arenas; terminal/reset data correct; real Godot rollouts update PPO; 16/32/64 batch comparison measured |
| 2.6 Check actor runtime in both exports | Browser/Android parity fixtures and timing | 1.4, 2.2 | Known observations match Python within max absolute action error 1e-4; local inference works offline |

Demo: Python can drive a batch of real Godot tables, and an exported policy-shaped test actor runs in both platforms. Label synthetic weights as test data, not trained skill. Gate: no long run until physics timestep, bridge reset semantics, and export parity pass.

### 3. Train purposeful policies and establish difficulty

| Task | Files / output | Depends on | Acceptance / check |
|---|---|---|---|
| 3.1 Implement drills and fixed baseline panel | Training scenario config and opponents | 2.5 | Baselines obey the same motor; held-out seeds never enter curriculum selection |
| 3.2 Run Python/SB3 PPO smoke and pilot training | `train.py`, configs, checkpoints, replay samples | 3.1 | 50k/500k run artifacts; actual PPO updates; improvement beyond random; no reward farming or cross-arena contamination |
| 3.3 Add frozen-opponent self-play | Opponent manifest, training loop | 3.2 | Fixed opponent per episode; historical pool retained; nominal-physics evaluation continues |
| 3.4 Train/fine-tune delay profiles | Candidate actors for all levels | 3.3 | At least three seeds examined; weaker candidates remain purposeful; physical limits identical |
| 3.5 Export and validate actors | `export_policy.py`, `models/`, ONNX companions | 2.6, 3.4 | Python/ONNX/GDScript parity; schema/checksums correct; actor size budgets met |
| 3.6 Run difficulty tournament | `evaluate.py`, difficulty report | 3.5 | Match-level ranking and strong-baseline gates measured; uncertainties and failed targets recorded |

Demo: all four difficulty selections visibly use bundled trained policies, and reports substantiate their ranking. Gate: final gameplay cannot substitute a scripted production bot. Keep the best accepted checkpoint for each level so unsuccessful retraining does not regress the release.

### 4. Finished game loop, artwork, and customization

| Task | Files / output | Depends on | Acceptance / check |
|---|---|---|---|
| 4.1 Complete match and lifecycle flow | Main scene/script and menus | 1.4, 3.5 | First to 7, pause/resume, re-serve, rematch, results, and Android back button behave consistently |
| 4.2 Finish original default table theme | Textures/materials and HUD | 1.4 | Sharp at phone density; puck visible at speed; visual/collider alignment checked |
| 4.3 Add cosmetic variants and persistence | Skin resources, Customize UI, settings | 4.2 | Independent table/puck/paddle selection persists; physics and difficulty hashes unchanged |
| 4.4 Add restrained effects and feedback | Audio, trails, contacts, optional haptics | 4.1–4.2 | No audio before web gesture; effect toggles work; no tracking obstruction |
| 4.5 Fit target screens and input | Layout, safe-area handling, settings | 4.1–4.4 | Small/tall phones, landscape fallback, desktop resizing, and touch offset checked |

Artwork and menu work may proceed after milestone 1 while training runs, but must not change frozen physical parameters without revalidation. This is a dependency note, not a requirement to spawn parallel agents.

### 5. Browser and Android end-to-end verification

| Task | Files / output | Depends on | Acceptance / check |
|---|---|---|---|
| 5.1 Validate final web export | PWA/export settings, web evidence | 3.6, 4.5 | Chrome, Firefox, Safari/WebKit smoke; desktop and touch; offline-after-cache; no console errors |
| 5.2 Validate final native Android export | Gradle export project/APK, Android evidence | 3.6, 4.5 | Open generated project in Android Studio; install actual APK to AVD; full game flow and offline first launch |
| 5.3 Profile and fix measured bottlenecks | Timing/size/memory reports | 5.1–5.2 | Policy, physics, render costs separated; no policy-worker/network requirement; soak stability |
| 5.4 Package reproducible handoff | README/runbook, builds, model report | 5.3 | Exact commands reproduce checks, training resume, model export, web build, and Android APK |

Deliver a tested APK and web export, plus an AAB build configuration for eventual store distribution. Record any unavailable signing credentials; do not invent them or publish to stores as part of this implementation plan.

## Verification and performance evidence

Use Godot assert-based check scenes/scripts and a small Python assert-based parity/bridge check. Use an existing browser automation tool for the exported canvas interaction; a native Android test must target the running APK through emulator input, not a responsive web preview. Add a browser harness or test runner only if existing tools cannot make the scenarios repeatable.

Required regression cases:

- Stationary paddle impact, moving paddle strike, direct rail reflection, double-rail rebound, near-tangent collision, post grazing, corner recovery, and maximum legal puck/paddle speeds.
- Randomized high-speed trajectories; no puck tunneling or hidden correction teleports in the validated speed range. If built-in CCD fails, first tune geometry/timestep/solver settings; then add a narrowly scoped swept-contact correction only with a failing scenario and cross-platform checks.
- Both paddle halves and goal-mouth barriers; no diagonal speed advantage; input cancellation; dragging outside the viewport.
- Correct score on fast legal goals, no score on post hits, no duplicate scores, and reset in the middle of an action repeat.
- Exact observation sample order, age/delay, coordinate rotation, initial history, and action clipping.
- Zero-action displacement and known-velocity travel over a specified number of actual physics ticks; accelerated training uses the same simulated duration as normal gameplay.
- SB3 VecEnv shape/dtype/reset metadata checks; bridge final observation versus reset observation; goal/timeout/continuing targets through SB3's rollout handling; transport failure cleanup and arena independence.
- At least 10k valid observation fixtures including real rollout states: maximum action difference <=1e-4 between Python, ONNX, and GDScript. Fix weight orientation/preprocessing before relaxing tolerance.
- Cosmetic switching must leave physics parameters/colliders and replayed control outcomes unchanged within the same build.

Use the same scripted collision scenarios on desktop, Android, and web. Do not promise bitwise determinism across Godot platforms: floating-point/contact differences can accumulate. Compare collision outcomes, short-horizon state errors, rule invariants, and evaluation distributions. Capture and explain systematic differences before accepting the policy.

End-to-end script for each release target:

1. Fresh launch → select level → start a match → move paddle → observe bot hit a puck.
2. Exercise an actual physics goal, pause/resume, first-to-7 completion, rematch, and return to menu.
3. Change table, puck, and both paddle appearances; restart and verify persistence.
4. Repeat for all four bundled RL actors; record the selected model hash.
5. Background/focus loss → paused state → explicit resume; no huge catch-up step or unintended score. On Android also test Back, activity restart, and safe areas.
6. Android: cold launch and complete match with network disabled. Web: complete asset caching, reload offline, and verify graceful behavior if browser storage is unavailable.
7. Run a 20-minute automated-match soak and record errors, memory trend, stalls, and actual frame timings.

Android test setup: inspect existing Android Studio, SDK, emulator, and AVDs before installing anything. Select an architecture compatible with the host, preferably ARM64 on Apple Silicon. Use one small-screen and one tall/notched profile, including an Android 15/API 35 image and the current available image. Log image, API, ABI, renderer, resolution, host, and APK build mode. Do not assume that the oldest engine-supported API is the game's tested minimum.

Android Studio and SDK/adb were found locally during planning; a Godot binary was not found on PATH or at `/Applications/Godot.app`. These are limited preflight observations, not proof of toolchain readiness. Verify actual engine location, JDK, export templates, Gradle dependencies, and emulator boot during implementation. [Godot Android setup](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html), [Android virtual device documentation](https://developer.android.com/studio/run/managing-avds)

Performance targets to measure after the first export:

| Metric | Initial acceptance target |
|---|---|
| Render responsiveness | Sustained 60 FPS on the chosen browser/AVD test configuration; report p50/p95/p99 frame interval, not only average FPS |
| Local actor execution | p95 <=1 ms per 30 Hz decision on each tested runtime |
| Actor assets | <50 KiB per runtime actor; <250 KiB for four actors/profiles |
| Input handling | Input command consumed by the next physics tick; measure touch-to-visible motion separately |
| Soak | No crashes/NaNs/missed legal goals; no persistent memory growth after warm-up |
| Offline | No model/asset fetch required for Android; web assets/model cached and versioned together |

Record actual APK/AAB, web WASM/PCK, textures, audio, model, and decoded-memory sizes separately. Godot's engine payload may outweigh the models. Report cold-load time and cache-load time under named conditions; do not claim that a 30 KiB actor makes the entire app 30 KiB.

Emulator success proves functional behavior on that virtual configuration. It does not establish low-end phone battery use, thermal behavior, or touch latency. Add a real mid-range Android device run when hardware is available, and mark that part unverified if it is not. If frame pacing fails, profile and reduce expensive effects/texture resolution before changing physics or model cadence.

## Runbook and final delivery

The implementing agent must create a README with exact working commands. The following are required entry points to implement, not commands already verified in this empty repository:

```sh
# Shared regression checks.
godot --headless --path . --script checks/physics_check.gd
godot --headless --path . --script checks/observation_check.gd

# Task-local Python checks and training.
uv run --project training python training/check.py
uv run --project training python training/train.py --config training/configs/smoke.json
uv run --project training python training/train.py --config training/configs/full.json --resume <checkpoint>
uv run --project training python training/export_policy.py --checkpoint <checkpoint> --output models/<level>
uv run --project training python training/evaluate.py --manifest models/manifest.json

# Export presets to create and verify.
godot --headless --path . --export-release Web builds/web/index.html
godot --headless --path . --export-debug Android builds/android/air-hockey-debug.apk
godot --headless --path . --export-release TrainingLinux builds/training/air-hockey.x86_64
```

Create target directories before exports. Keep training scene/bridge and test assets out of production presets, including JSON/bin runtime model resources explicitly. Ensure no excluded training class is referenced by the release scene. Configure Android's generated Gradle project so it opens in Android Studio as requested. Include the exact browser serving method and correct WASM MIME type in the runbook.

Final deliverables:

- Source project with pinned engine, stable SB3/PyTorch/Python dependencies and any reproducible bridge adaptations, original licensed assets, and no global Python dependency assumptions.
- Web/PWA build, installable Android APK, and reproducible Android/AAB configuration.
- Four qualified RL actor artifacts and profiles; corresponding ONNX exports; model/physics/schema manifests.
- Training configuration, checkpoint/resume instructions, frozen opponent pool, and representative replay samples.
- Model parity results, physics checks, difficulty tournament report with confidence intervals, and observed performance metrics.
- Browser and Android Studio/AVD evidence: screenshots or short recordings, build/model hashes, exact configurations, and logs.
- A short list of remaining unverified claims or failed gates. Launching an app, running a training process, or seeing GPU utilization alone is not completion.

## Risks and change rules

| Risk | Required response |
|---|---|
| Training physics differs from the game | Shared Arena scene, frozen physics hash, exact stepping checks; retrain after meaningful changes |
| RL learns a reward exploit or brittle self-play | Inspect replays; mixed frozen opponents; held-out match evaluation; remove exploitative shaping |
| Four labels do not produce distinct skill | Tournament and human checks; qualify/fine-tune checkpoints before release |
| Runtime becomes platform-specific | GDScript MLP; companion ONNX; parse/export checks without C# dependencies |
| Built-in CCD misses a valid fast collision | Preserve a failing fixture; tune first; make a bounded correction only if necessary |
| Web or Android export fails late | Export both in milestone 1, then rerun after actor integration and final assets |
| Slow training despite an available H100 | Profile simulation/bridge first; use CPU batch/process parallelism before GPU scaling |
| Adapter timeout metadata biases value targets | Supply terminal_observation and TimeLimit.truncated correctly; check SB3's existing handling; do not add a second bootstrap correction |
| Release model/config updates break compatibility | Bundle physics, schema, difficulty, and actor versions together; fail visibly on incompatible assets |

Keep the last accepted model bundle and release build. New training runs produce candidates, not automatic replacements. If a candidate regresses, restore the previous actor/profile bundle together. Settings schema changes must preserve usable defaults. Save meaningful implementation checkpoints in version control; do not commit private signing keys or huge run outputs.

## Coding-agent instruction

Implement this plan in dependency order and finish the authorized local builds, Python/Stable Baselines3 PPO training, and browser/Android verification. Start with milestone 1 and show the first playable web and Android prototype before extending training runs. Follow the user's FFF-first discovery preference, use read-only filesystem/rg fallback when indexing is unavailable, and keep Python in the project-local uv environment. Reuse Godot RL Agents transport/integration after checking the pinned source; do not replace Godot physics with a separate Python approximation or implement a custom PPO trainer. Keep deviations and failed acceptance gates visible. The final bot at every difficulty must be a bundled trained RL actor controlling a physically moving paddle.
