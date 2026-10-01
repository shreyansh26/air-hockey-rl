# Mobile UI and input — 0.1.2

The court now sits below a safe-area header with You/Bot scores, difficulty,
first-to-seven context and an SVG pause icon. A finish-colored background fills
the window and recent-app card. The court and pieces retain their proportions.

Settings use large switch artwork and whole-row touch targets. Play, Resume,
Rematch and Done have a clearer primary style. Appearance rows are compact on
phones; narrower layouts stack the label above its picker. Dropdowns, sliders
and menus share the game palette. The pause artwork avoids missing-font glyphs.

Finger tracking changes the position response from 12 to 30 per second and
updates the motor command immediately on drag events. Event batching is
disabled during play and restored in menus. The shared speed, acceleration,
colliders, physics timing and trained actors are unchanged.

| Verification | Result and evidence |
| --- | --- |
| Tracking | At a scripted 600 logical units/s, mean follow distance falls from 44.81 to 15.00 units: **66.5% lower**. Peak speed is 750, below the shared 1050 limit; final settling error is below 0.001 units. [Runnable check](../checks/touch_serve_check.gd), [summary](mobile-ui-0.1.2.json) |
| Layout/settings | Six portrait, tablet and desktop layouts pass bounds, round pieces, header controls, touch inversion and panel checks. Fresh/migrated settings, explicit sound choices, previews and launch artwork pass |
| Android 15 | Final QA APK on 1080×2424 ARM64: four actor hashes and contacts, native drag, both goal pockets, first-to-seven/rematch, pause/Home/Back, sound both ways, appearance persistence and offline first launch pass. 113 physics cases and 40,000 parity observations pass. [Report](android-ui-0.1.2-api35.json) |
| Android 16 | Same final QA APK on a 720×1280, 320-dpi ARM64 AVD: the same full regression, physics and parity checks pass. [Report](android-ui-0.1.2-api36-small.json) |
| Actual OnePlus | Production version 0.1.2/code 3 installed; pulled installed APK matches the production build SHA. Settings remain byte-for-byte unchanged across installation. Full-screen menu rendered with the user's saved colors and difficulty. [Installation proof](mobile-ui-phone-0.1.2.json) |
| Web | Final uncached in-app browser build renders the SVG header icon, plays the actual Medium actor, accepts mouse dragging and pauses. The paddle moves from (299.61, 832.46) to (170.21, 779.95); release clears input. No captured console errors. [Report](web-ui-0.1.2.json) |
| Packaging | Final production web/APK/AAB audited; all four actor hashes and 139,714 policy bytes retained; training, QA and ONNX excluded. [Build audit](builds.json) |

Visual review: [gameplay](screenshots/mobile-0.1.2-gameplay.png),
[switches](screenshots/mobile-0.1.2-settings-off.png),
[small-screen settings](screenshots/mobile-0.1.2-small-emulator-5562-settings.png),
[recent-app card](screenshots/mobile-0.1.2-recents.png),
[web pause](screenshots/mobile-0.1.2-web-pause.jpg).

The native harness uses the actual Godot widget tree because Android's UI tree
does not expose controls drawn inside the game surface. Initial emulator runs
were interrupted by an unrelated Digital Wellbeing ANR dialog and shader-cache
recompilation. The dialog was closed on the disposable AVD; both final runs
completed against the same recorded APK. Cold launch waits allow shader setup.
Web verification used a fresh local origin after the old PWA kept its cached
package. Subsequent local rebuilds still require closing the old game tab.

These follow-distance measurements are not physical touch-to-display latency.
No new 20-minute soak, battery/thermal test or human difficulty qualification
was run. The earlier web-memory and AVD frame-pacing failures remain open in
[STATUS.md](STATUS.md). Recorded gain-12 human-controller comparisons remain
historical; the new gain-30 profile has not received a difficulty tournament.

Switch theming uses native Godot controls and their
[documented icon properties](https://docs.godotengine.org/en/4.5/classes/class_checkbutton.html);
drag batching follows the [Input API](https://docs.godotengine.org/en/4.5/classes/class_input.html).
