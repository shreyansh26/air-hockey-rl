# Implementation gates

Pinned engine: Godot **4.5.1 stable**, standard GDScript, Compatibility renderer.
Shared physics: GodotPhysics2D, **120 Hz**, time scale **1**, **4 ticks/action**.

Gameplay loads one of four trained actors and fails visibly if it is missing
or incompatible. Training, QA, critics, optimizers, and ONNX companions are
excluded from production exports.

| Gate | State |
| --- | --- |
| Shared physics checks | Passed 113 cases on headless desktop, web, API 35 and API 36.1, including four angled exits, post rebounds and bounded escape recovery |
| Early browser export | Played in Chrome; final-model Firefox render/contact/pause smoke passed |
| Early native Android export | Actual APK played on isolated API 35 and API 36.1 ARM64 AVDs; Gradle project opened/built in Android Studio |
| Bridge and observation semantics | Passed real four-tick travel, terminal/reset, timeout, world isolation, optimizer resume, top-side evaluation and narrow match resets |
| PPO smoke/pilot and resume | Three independent smoke seeds, 500k pilot, 5M original full run, interruption/resume verified |
| Four trained actor exports/parity | Selected strategic actors, 10k observations each across all four delays; max action error 1.38e-6. Web and both native QA APKs pass 40k comparisons |
| Difficulty tournament | Passed fresh 2,000 complete balanced matches under corrected goals: Medium>Easy 64.5%, Hard>Medium 94.5%, Insane>Hard 93.25%; Insane beats the strong interceptor 96.75% and delayed puck-chaser 100% |
| Human playtest | Beginner/expert calibration unverified |
| Native E2E/offline | API 35 and API 36.1 ARM64: all four hashes/contacts, touch, pause/resume, angled goals at both ends, vanish/restore, first-to-seven, rematch, Home/Back, cosmetics persistence, offline first launch and 113 cases pass |
| Web E2E/offline | In-app four-level goal/return/rematch, animation pause, 113 physics cases and 40k parity pass. Production IAB/Firefox/Safari render/control smoke and cached offline loading pass; Firefox requires an online cache warm-up. Chrome disconnected, user authorized alternatives |
| Soak | All three runtimes completed 20 active minutes with zero escapes, stalls and NaNs: nine matches on each AVD, seven on web. Native memory is flat after warm-up; web QA memory grows, so its memory gate remains failed |
| Performance | Recent actor p95: web 0.300 ms, API 35 0.369 ms, API 36 0.342 ms. Full-soak frame p50/p95/p99: web 16.6/16.6/16.8 ms, API 35 37.7/62.5/69.1 ms, API 36 16.6/31.2/56.9 ms. AVD frame-pacing gates fail under the recorded concurrent validation load |
| Packaging | Production web/APK/AAB/TrainingLinux rebuilt and audited; actual production web PCK goal-flow check and production APK smokes pass. Runtime actors/profiles 139,714 bytes; training/QA/ONNX excluded |

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

Goal correction: the old scoring strip rejected legal angled exits.
Shared Arena now uses the actual mouth after the full puck crosses; unexpected
escapes freeze and re-serve without a point. Goal-only visual offset/fade never
moves the physical body. Original checkpoint physics provenance is retained;
fresh tournament requalified the exact weights under the new runtime hash.

The web memory failure remains unresolved. Cached DOM bindings and Reduced
effects did not remove the counter growth; those unproven changes were not
promoted. The original implementation task owns the remaining performance
investigation. This does not qualify production memory as stable.
