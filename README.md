🎥 rec.nvim

A minimal, native Neovim screen recording plugin — built for developers.

rec.nvim lets you record your Neovim sessions directly from the editor using a fast Rust backend (rec-cli).
It focuses on clarity, reliability, and developer UX, not bloated overlays or external GUIs.

✨ Features

🔴 One-command recording

⏱ Live recording timer

⌨️ Keystroke overlay (for tutorials & demos)

🪟 Floating HUD (non-intrusive)

📁 Automatic file saving

🧠 Native Neovim Lua (no external UI plugins required)

⚡ Rust-powered backend for performance & stability

🧩 Architecture
rec.nvim/
├── lua/rec/
│   ├── init.lua        -- Core plugin logic
│   ├── dashboard.lua  -- Recording dashboard (read-only)
│   ├── keys.lua       -- Keystroke capture & rendering
│   ├── geometry.lua  -- Floating window placement helpers
│   └── config.lua    -- User configuration
├── crates/
│   └── rec-cli/       -- Rust recording backend (ffmpeg-based)
└── README.md


Lua handles UX, state, and editor integration

Rust (rec-cli) handles screen/window capture and encoding

Communication happens via jobstart (no blocking)

🚀 Installation
Requirements

Neovim 0.9+

ffmpeg installed and available

macOS (Linux support planned)

Using lazy.nvim
{
  "willsantiagomedina/rec.nvim",
  config = function()
    require("rec").setup()
  end,
}


⚠️ Make sure rec-cli is built (see below).

🛠 Building the Recorder (rec-cli)
cd ~/dev/rec.nvim/crates/rec-cli
cargo build


Ensure the binary exists at:

~/dev/rec.nvim/crates/rec-cli/target/debug/rec-cli


rec.nvim does not rely on $PATH — the absolute path is used for safety.

🎬 Usage
Start Recording
:RecStart


Shows a floating HUD

Starts timer

Enables keystroke overlay

Stop Recording
:RecStop


Stops recording

Saves video to disk

Cleans up overlays

Open Dashboard
:RecDashboard


Lists saved recordings

Navigate with j / k

Press <Enter> to open

q or <Esc> to close

📂 Output Location

By default, recordings are saved to:

~/Videos/nvim-recordings/


Filenames include timestamps for easy sorting.

⚙️ Configuration
require("rec").setup({
  output_dir = "~/Videos/nvim-recordings",
  show_keystrokes = true,
  hud = {
    position = "top-right",
  },
})


More options coming as the plugin stabilizes.

🧠 Design Philosophy

Stability first

No autocommand spam

No CursorMoved hooks

No hard dependency on UI plugins

Readable Lua > clever hacks

This plugin is built to be hackable, debuggable, and trustworthy.

🛣 Roadmap

⏸ Pause / Resume recording

🪟 Record current window only

🧭 Timeline markers

🖼 Thumbnails in dashboard

📤 Export / upload helpers

🤝 Contributing

PRs and ideas welcome — especially around:

Linux support

FFmpeg capture strategies

UI ergonomics

Performance tuning

📜 License

MIT
