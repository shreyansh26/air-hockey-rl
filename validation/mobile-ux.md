# Mobile usability update — 0.1.1

The shipped view uniformly fits one fixed 600×1000 logical court. It keeps
puck/paddle circles aligned with their colliders on every screen, with no
device-specific model, physics, or observation changes. On the OnePlus
1080×2412 display, the outer court is approximately 1080×1715: full width,
71% height, with space above and below. This replaces the experimental
full-height stretch, which elongated pieces. Changing the canonical physical
court would require one new model qualification, rather than one per device.

The app is immersive and edge-to-edge. Scores and Pause are on the board;
GLIDE appears only at its center. All input instructions were removed.
Native touch follows the finger through the same inverse display mapping,
with the existing physical speed/acceleration limits. Both paddles remain
active while the puck waits. New serves begin at the centerline, choose a
random first recipient, and subsequently launch toward the conceding player.
Opening wait is 0.7s; goal fade/presentation is 0.55s, followed by 0.45s before
re-serve. Legal paddle contact can redirect the released puck immediately.

Sound defaults off, including one-time migration of existing preferences;
explicit subsequent choices persist. Settings and Pause both offer Sound.
Customization has live viewport previews and colored/perforated swatches.
Original Glide artwork replaces engine/system branding; a silent 0.5s intro
is nonblocking and skipped with Reduced effects.

| Check | Evidence |
| --- | --- |
| Layout | Six viewports, actual layout frames, maximum proportional fit, round pieces, bounds, board score positions, pause targets, inverse touch mapping and scrollable menus pass |
| Input/serve | Real Godot InputEvents exercise countdown/goal movement, edge reach, cancellation, focus/Back, random/conceding serves, and unchanged training resets |
| Settings/previews/launch | Isolated fresh/migrated/corrupted settings, explicit sound persistence, actual preview textures, selected colors and original splash/icon configuration pass |
| Android 15/16 | Final QA APK SHA matches both [native reports](android-emulator-5560.json); [Android 16 report](android-emulator-5562.json). Four levels, hashes, bot contacts, native drag, first-to-seven/rematch, both goal pockets, pause/Home/Back, cosmetics persistence, offline first launch, 113 physics cases and 40k parity checks per device pass |
| Real OnePlus | Production 0.1.1/code2 installed and launched; saved settings confirm sound=false. [Actual proportional gameplay](screenshots/mobile-ux-phone.png) |
| Web | Final Safari build plays with real bot/human contacts, pause and sound control, and live finish changes; [customization screenshot](screenshots/mobile-ux-customization.png). Firefox candidate also rendered, played, paused and accepted physics commands in touch emulation. Final six-size layout coverage is headless; Safari final view is desktop |
| Packaging | Final production web/APK/AAB [audit](builds.json) passes; four unchanged actor hashes, 139714 policy bytes, no QA/training/ONNX in production |

The in-app browser's fresh QA startup failed with
`WebAssembly.instantiate(): Import #0 "env": module is not an object or function`.
Its JavaScript/WASM hashes match the previously working build. The cause is
unresolved; Safari supplies final web runtime verification. Firefox's active
user-controlled responsive tab was preserved. No new 20-minute soak or
battery/thermal benchmark was run; the older web memory and AVD frame-pacing
failures remain open.

The Android harness is restricted to disposable emulators. It waits for the
activity transition before taps and reads archived fade telemetry so shorter
animations cannot be confused with a later goal. The real phone received only
production installation/launch verification, without clearing its app data
or changing its networking.
