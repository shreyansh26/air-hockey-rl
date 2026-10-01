# Licenses and pinned sources

Glide artwork (`icon.svg`, adaptive icons, boot-splash SVG/PNG, pause/switch/slider SVGs, procedural table shader and body drawings) and
`impact.wav` (a synthesized PCM hit) were created for this project. No reference
screenshot artwork is included. The default font is the Godot-bundled Noto Sans
(SIL Open Font License). Godot 4.5.1 is MIT licensed.

The training transport extends `godot_rl.core.godot_env.GodotEnv`; the VecEnv
boundary uses SB3's `VecEnv` and `VecExtractDictObs` rather than a custom network
or learner. Python source revision:
`edbeeching/godot_rl_agents@207b6f476f5846f33d08b92c7a350147e7b78bf5`.
The audited GDScript Sync source revision:
`edbeeching/godot_rl_agents_plugin@998c357a0cd09b37f40a36d70c7867fc9f682338`.

The narrow Sync adaptation preserves the 4-byte little-endian JSON framing and
handshake/env_info/action/reset messages. It removes ONNX/.NET/demo paths,
uses 120 Hz with time scale 1, pauses at the synchronized four-step boundary,
isolates worlds, validates packets, reports termination/truncation independently,
and preserves final observations before resetting. The Python adaptation fixes
tokenization of `--fixed-fps 120`, binds loopback with finite timeouts, rejects
EOF/oversized packets, and owns child/socket cleanup. PPO is unmodified SB3.

Upstream's dependency constraints require SB3 <=2.4 and Gymnasium <=1.0. This
project therefore pins SB3 2.4.0, Gymnasium 1.0.0 and NumPy 1.26.4, together with
PyTorch 2.8.0. Exact transitive versions are in `training/uv.lock`.

## Godot RL Agents MIT license

Copyright (c) 2021 Edward Beeching

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
