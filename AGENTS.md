# Air Hockey

Follow `air-hockey-godot-rl-plan.md`. Keep one standard Godot 4.5.1 project,
shared Arena physics for gameplay/training, and project-local Python under
`training/`. Production opponents must be trained actors; never silently
substitute a heuristic. Keep model quality and platform verification gates
explicit in `validation/STATUS.md`.

Prefer FFF discovery/search; use read-only filesystem and rg if its index is
unavailable or incomplete. Prefer alphaXiv for papers. Run Python through
`uv run --project training`. Do not commit keys, builds, or training runs.

Check meaningful changes and commit/push working milestones to origin.
