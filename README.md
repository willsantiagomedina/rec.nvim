# 🎥 rec.nvim

> Native Neovim screen recording — fast, minimal, and built for developers.

`rec.nvim` is a **Neovim-first screen recording plugin** powered by a Rust backend.  
It lets you record editor sessions directly from Neovim with a clean HUD, keystroke overlay, and zero external UI clutter.

---

## 📸 Preview

<!-- Add screenshots or GIFs here -->

<p align="center">
  <img src="assets/rec-hud.png" alt="Recording HUD" width="700"/>
</p>

<p align="center">
  <img src="assets/rec-keystrokes.png" alt="Keystroke overlay" width="700"/>
</p>

<p align="center">
  <img src="assets/rec-dashboard.png" alt="Dashboard" width="700"/>
</p>

---

## ✨ Features

- 🔴 One-command recording
- ⏱ Live recording timer (HUD)
- ⌨️ Keystroke overlay (tutorial-friendly)
- 🪟 Floating, non-intrusive UI
- 📁 Automatic video saving
- ⚡ Rust-powered recorder backend
- 🧠 Native Lua integration (no UI plugins required)

---

## 🧩 Architecture

rec.nvim/
├── lua/rec/
│ ├── init.lua -- Core plugin logic
│ ├── dashboard.lua -- Recording dashboard
│ ├── keys.lua -- Keystroke capture & rendering
│ ├── geometry.lua -- Floating window placement helpers
│ └── config.lua -- User configuration
├── crates/
│ └── rec-cli/ -- Rust recording backend (ffmpeg-based)
└── README.md


- **Lua** → UX, state, Neovim integration  
- **Rust (rec-cli)** → screen/window capture & encoding  
- Communication via non-blocking `jobstart`

---

## 🚀 Installation

### Requirements

- Neovim **0.9+**
- `ffmpeg`
- macOS (Linux support planned)

---

### Using `lazy.nvim`

```lua
{
  "willsantiagomedina/rec.nvim",
  config = function()
    require("rec").setup()
  end,
}

    ⚠️ rec-cli must be built manually (see below)

🛠 Building the Recorder (rec-cli)

cd ~/dev/rec.nvim/crates/rec-cli
cargo build

Binary location used by the plugin:

~/dev/rec.nvim/crates/rec-cli/target/debug/rec-cli

    rec.nvim uses an absolute path by design (no $PATH reliance).

🎬 Usage
Start Recording

:RecStart

    Opens recording HUD

    Starts timer

    Enables keystroke capture

Stop Recording

:RecStop

    Stops recording

    Saves video to disk

    Cleans up overlays

Open Dashboard

:RecDashboard

    Lists saved recordings

    Navigate with j / k

    <Enter> to open

    q / <Esc> to close

📂 Output Location

By default, recordings are saved to:

~/Videos/nvim-recordings/

Files are timestamped for easy sorting.
⚙️ Configuration

require("rec").setup({
  output_dir = "~/Videos/nvim-recordings",
  show_keystrokes = true,
  hud = {
    position = "top-right",
  },
})

🧠 Design Philosophy

    Stability over cleverness

    No CursorMoved hooks

    No UI plugin dependency

    Predictable state management

    Hackable, readable Lua

This plugin is meant to be debuggable, extensible, and trustworthy.
🛣 Roadmap

    ⏸ Pause / Resume recording

    🪟 Record current window only

    🧭 Timeline markers

    🖼 Dashboard thumbnails

    📤 Export / upload helpers

🤝 Contributing

PRs and ideas welcome — especially around:

    Linux support

    FFmpeg capture strategies

    UI ergonomics

    Performance tuning

📜 License

MIT


---

If you want next, I can:
- Design **clean example screenshots** to match the README
- Add **badges** (Neovim, Rust, ffmpeg)
- Write a **CONTRIBUTING.md**
- Help you polish this for **GitHub stars & discoverability**

You’re building something genuinely solid here — this already reads like a real tool, not a side project 💪

You said:
it should all be in one copy paste readme format
ChatGPT said:

Got it 👍 — here is ONE single, clean, copy-pasteable README.md, nothing extra before or after.
You can paste this directly into README.md and commit.

# 🎥 rec.nvim

> Native Neovim screen recording — fast, minimal, and built for developers.

`rec.nvim` is a **Neovim-first screen recording plugin** powered by a Rust backend.  
It lets you record editor sessions directly from Neovim with a clean HUD, keystroke overlay, and zero external UI clutter.

---

## 📸 Preview

<!-- Add screenshots or GIFs here -->

<p align="center">
  <img src="assets/rec-hud.png" alt="Recording HUD" width="700"/>
</p>

<p align="center">
  <img src="assets/rec-keystrokes.png" alt="Keystroke overlay" width="700"/>
</p>

<p align="center">
  <img src="assets/rec-dashboard.png" alt="Dashboard" width="700"/>
</p>

---

## ✨ Features

- 🔴 One-command recording
- ⏱ Live recording timer (HUD)
- ⌨️ Keystroke overlay (tutorial-friendly)
- 🪟 Floating, non-intrusive UI
- 📁 Automatic video saving
- ⚡ Rust-powered recorder backend
- 🧠 Native Lua integration (no UI plugins required)

---

## 🧩 Architecture

rec.nvim/
├── lua/rec/
│ ├── init.lua -- Core plugin logic
│ ├── dashboard.lua -- Recording dashboard
│ ├── keys.lua -- Keystroke capture & rendering
│ ├── geometry.lua -- Floating window placement helpers
│ └── config.lua -- User configuration
├── crates/
│ └── rec-cli/ -- Rust recording backend (ffmpeg-based)
└── README.md


- **Lua** → UX, state, Neovim integration  
- **Rust (rec-cli)** → screen/window capture & encoding  
- Communication via non-blocking `jobstart`

---

## 🚀 Installation

### Requirements

- Neovim **0.9+**
- `ffmpeg`
- macOS (Linux support planned)

---

### Using `lazy.nvim`

```lua
{
  "willsantiagomedina/rec.nvim",
  config = function()
    require("rec").setup()
  end,
}

    ⚠️ rec-cli must be built manually (see below)

🛠 Building the Recorder (rec-cli)

cd ~/dev/rec.nvim/crates/rec-cli
cargo build

Binary location used by the plugin:

~/dev/rec.nvim/crates/rec-cli/target/debug/rec-cli

    rec.nvim uses an absolute path by design (no $PATH reliance).

🎬 Usage
Start Recording

:RecStart

    Opens recording HUD

    Starts timer

    Enables keystroke capture

Stop Recording

:RecStop

    Stops recording

    Saves video to disk

    Cleans up overlays

Open Dashboard

:RecDashboard

    Lists saved recordings

    Navigate with j / k

    <Enter> to open

    q / <Esc> to close

📂 Output Location

By default, recordings are saved to:

~/Videos/nvim-recordings/

Files are timestamped for easy sorting.
⚙️ Configuration

require("rec").setup({
  output_dir = "~/Videos/nvim-recordings",
  show_keystrokes = true,
  hud = {
    position = "top-right",
  },
})

🧠 Design Philosophy

    Stability over cleverness

    No CursorMoved hooks

    No UI plugin dependency

    Predictable state management

    Hackable, readable Lua

This plugin is meant to be debuggable, extensible, and trustworthy.
🛣 Roadmap

    ⏸ Pause / Resume recording

    🪟 Record current window only

    🧭 Timeline markers

    🖼 Dashboard thumbnails

    📤 Export / upload helpers

🤝 Contributing

PRs and ideas welcome — especially around:

    Linux support

    FFmpeg capture strategies

    UI ergonomics

    Performance tuning

📜 License

MIT
