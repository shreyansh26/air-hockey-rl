# Implementation gates

Pinned engine: Godot **4.5.1 stable**, standard GDScript, Compatibility renderer.
Shared physics: GodotPhysics2D, **120 Hz**, time scale **1**, **4 ticks/action**.

Gameplay loads one of four trained actors and fails visibly if it is missing
or incompatible. Training, QA, critics, optimizers, and ONNX companions are
excluded from production exports.

| Gate | State |
| --- | --- |
| Shared physics checks | Passed 108 cases on headless desktop, web, and API 35 QA APK |
| Early browser export | Played in Chrome; final-model Firefox render/contact/pause smoke passed |
| Early native Android export | Actual APK played on isolated API 35 and API 36.1 ARM64 AVDs; Gradle project opened/built in Android Studio |
| Bridge and observation semantics | Passed real four-tick travel, terminal/reset, timeout, world isolation, optimizer resume, top-side evaluation and narrow match resets |
| PPO smoke/pilot and resume | Three independent smoke seeds, 500k pilot, 5M original full run, interruption/resume verified |
| Four trained actor exports/parity | Selected strategic actors, 10k observations each across all four delays; max action error 1.38e-6. Web and both native QA APKs pass 40k comparisons |
| Difficulty tournament | Passed 2,000 complete balanced matches: Medium>Easy 65.25%, Hard>Medium 94.5%, Insane>Hard 92.75%; Insane beats strong interceptor 97% and delayed puck-chaser 100% |
| Human playtest | Beginner/expert calibration unverified |
| Native E2E/offline | API 35 and API 36.1 ARM64: all four hashes, actual contacts, touch, pause/resume, first-to-seven, rematch, Home/Back, cosmetics persistence, offline first launch, and 108 physics cases pass |
| Web E2E/offline | In-app browser four-level flow/drag/physics/parity pass; Firefox cached offline launch and real tab-switch pause/explicit resume pass. Final Safari smoke pending; Chrome automation disconnected, user authorized alternatives |
| Soak | First 20 active minutes completed on all three runtimes without invalid states. Final bounded-memory recorder soak running after static-table render caching |
| Performance | Actor p95 below 1 ms on all tested runtimes. API 35 SwiftShader at 1080×2424 misses 60 FPS; API 36 host GPU and web substantially faster. Final distributions pending |
| Packaging | Actual production web pack/APK/AAB hashes audited; four runtime actors/profiles about 136 KiB total. Final rebuild/audit pending after table-cache change |

The original policies failed qualification and were replaced. See
[bot-quality analysis](../docs/bot-quality.md) for reward/rollout diagnosis,
matched fixed-quota shot panels, recorded trajectories, and current match
evidence. The selected policies improve verified returns from 41% to 96.5%
on the matched 200-shot Insane-delay panel. Full match results are in
[difficulty.json](difficulty.json).

Real-phone battery/thermal/touch latency, beginner/expert human labels, and
release signing credentials are unavailable. The delivered APK/AAB use the
debug key; no store publication is performed.

Builds, training runs, and raw logs are ignored. This file records measured
results as checks finish; no pending gate is implied complete by a build.
