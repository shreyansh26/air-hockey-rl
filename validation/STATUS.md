# Implementation gates

Pinned engine: Godot **4.5.1 stable**, standard GDScript, Compatibility renderer.
Shared physics: GodotPhysics2D, **120 Hz**, time scale **1**, **4 ticks/action**.

The initial milestone uses a visibly marked development opponent. Final
production exports must load four trained actors and must fail visibly if an
actor is missing or incompatible.

| Gate | State |
| --- | --- |
| Shared physics checks | In progress |
| Early browser export | In progress |
| Early native Android export | In progress |
| Bridge and observation semantics | Pending |
| PPO smoke/pilot and resume | Pending |
| Four trained actor exports/parity | Pending |
| Difficulty tournament/human playtest | Pending |
| Final platform/offline/soak checks | Pending |

Builds, training runs, and raw logs are ignored. This file records measured
results as checks finish; no pending gate is implied complete by a build.
