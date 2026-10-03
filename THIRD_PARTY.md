# Artwork and third-party licenses

Glide's icons, splash artwork, UI artwork, procedural table and body drawings,
and synthesized `impact.wav` were created for this project. The default font
is Godot's bundled Noto Sans, licensed under the SIL Open Font License.
Godot 4.5.1 is MIT licensed.

Training uses Stable-Baselines3 PPO, PyTorch, Gymnasium, and Godot RL Agents.
Pinned Python dependencies are recorded in `training/pyproject.toml` and
`training/uv.lock`.

The Godot/Python transport adapts the MIT-licensed Godot RL Agents projects:

- Python: `edbeeching/godot_rl_agents@207b6f476f5846f33d08b92c7a350147e7b78bf5`
- GDScript Sync: `edbeeching/godot_rl_agents_plugin@998c357a0cd09b37f40a36d70c7867fc9f682338`

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
