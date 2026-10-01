# Implementation gates

Pinned engine: Godot **4.5.1 stable**, standard GDScript, Compatibility renderer.
Shared physics: GodotPhysics2D, **120 Hz**, time scale **1**, **4 ticks/action**.

The initial milestone uses a visibly marked development opponent. Final
production exports must load four trained actors and must fail visibly if an
actor is missing or incompatible.

| Gate | State |
| --- | --- |
| Shared physics checks | Passed 108 cases on headless desktop, web, and API 35 QA APK |
| Early browser export | Played in Chrome; final-model Firefox render/contact/pause smoke passed |
| Early native Android export | Actual APK played on isolated API 35 and API 36.1 ARM64 AVDs; Gradle project opened/built in Android Studio |
| Bridge and observation semantics | Passed real four-tick travel, terminal/reset, timeout, world isolation, optimizer resume, top-side evaluation and narrow match resets |
| PPO smoke/pilot and resume | Three independent smoke seeds, 500k pilot, 5M original full run, interruption/resume verified |
| Four trained actor exports/parity | Original four actors bundled; 10k observations each, max action error below 1e-6; quality failed |
| Difficulty tournament/human playtest | Initial 400-match gates failed; Insane lost all 400 strong-baseline matches. Human skill labels unverified |
| Final platform/offline/soak checks | API 35 four-level E2E/offline/parity passed and 20-minute initial soak completed. API 36.1 failed Insane contact check. New selected-model verification remains open |

The original policies are unqualified. See [bot-quality analysis](../docs/bot-quality.md)
for reward/rollout diagnosis and controlled before/after results. A revised PPO
candidate greatly improves pursuit; further goal-focused experiments and
complete delayed-chaser/strong-baseline matches are running before replacement.

Builds, training runs, and raw logs are ignored. This file records measured
results as checks finish; no pending gate is implied complete by a build.
