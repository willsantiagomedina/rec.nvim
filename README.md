# rec.nvim 🎥

> A powerful Neovim plugin for recording your editing sessions with keystroke overlay and real-time timer

[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
[![Neovim](https://img.shields.io/badge/Neovim-0.8%2B-green.svg)](https://neovim.io)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Rust](https://img.shields.io/badge/rust-1.70%2B-orange.svg)](https://www.rust-lang.org)

## ✨ Features

- 🖥️ **Screen Recording** - Capture full screen or specific windows with AVFoundation backend
- ⌨️ **Keystroke Overlay** - Real-time display of keystrokes with beautiful symbols and collapsing
- ⏱️ **Recording Timer HUD** - Live timer showing recording duration
- 🎨 **Customizable UI** - Configure overlay position, opacity, colors, and dimensions
- ⚡ **FFmpeg Backend** - Powered by Rust CLI for high performance
- 📹 **Multiple Formats** - MP4 output with QuickTime compatibility
- 🎯 **Window Recording** - Capture specific windows with automatic geometry detection (yabai)
- 📊 **Recording Dashboard** - View and manage your recording history
- ⏸️ **Pause/Resume** - Pause and resume recordings on the fly

## 📋 Requirements

- **Neovim 0.8+** - Modern Neovim with Lua API
- **macOS** - Currently supports macOS with AVFoundation framework
- **FFmpeg** - Must be installed and available in PATH
  ```bash
  brew install ffmpeg
  ```
- **Rust Toolchain** - For building the CLI backend
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```
- **Screen Recording Permissions** - Enable in System Settings → Privacy & Security → Screen Recording

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "willsantiagomedina/rec.nvim",
  build = "cd crates/rec-cli && cargo build --release",
  config = function()
    require("rec").setup({
      -- Your configuration here
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "willsantiagomedina/rec.nvim",
  run = "cd crates/rec-cli && cargo build --release",
  config = function()
    require("rec").setup({
      -- Your configuration here
    })
  end
}
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/willsantiagomedina/rec.nvim.git ~/.local/share/nvim/site/pack/plugins/start/rec.nvim
   ```

2. Build the CLI:
   ```bash
   cd ~/.local/share/nvim/site/pack/plugins/start/rec.nvim
   cd crates/rec-cli
   cargo build --release
   ```

3. Add to your Neovim configuration:
   ```lua
   require("rec").setup()
   ```

## ⚙️ Configuration

### Default Configuration

```lua
require("rec").setup({
  overlay = {
    -- Position: "bottom-right", "bottom-center", "top-right", "top-center"
    position = "bottom-right",
    
    -- Maximum keystrokes to show in overlay
    max_keys = 5,
    
    -- Overlay opacity (0-100, where 0 is transparent, 100 is opaque)
    opacity = 95,
    
    -- Window dimensions
    width = 32,
    height = 5,
    
    -- Padding from edges (rows/cols)
    padding = {
      row = 1,
      col = 2,
    },
    
    -- Custom position function (overrides position if set)
    -- Should return { row = number, col = number, anchor = string }
    custom_position = nil,
  },
  
  recording = {
    -- Output directory for recordings (supports ~/ expansion)
    output_dir = "~/Videos/nvim-recordings",
    
    -- Auto-open video after stopping recording
    auto_open = false,
    
    -- Command to open video (leave nil for system default)
    -- Examples: "vlc", "mpv", "open" (macOS), "xdg-open" (Linux)
    open_command = nil,
  },
  
  keys = {
    -- Enable keystroke overlay
    show_overlay = true,
    
    -- Maximum repeat count before collapsing (e.g., jjj -> j×5)
    max_repeat_count = 3,
    
    -- Ignore navigation key repetition (h,j,k,l,w,b,e)
    ignore_navigation = true,
    
    -- Ignore mouse events
    ignore_mouse = true,
    
    -- Key separator in overlay
    separator = "  ·  ",
  },
})
```

### Configuration Options

#### Overlay Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `position` | string | `"bottom-right"` | Overlay position: `"bottom-right"`, `"bottom-center"`, `"top-right"`, `"top-center"` |
| `max_keys` | number | `5` | Maximum number of keystrokes to display |
| `opacity` | number | `95` | Overlay opacity (0-100) |
| `width` | number | `32` | Overlay window width |
| `height` | number | `5` | Overlay window height |
| `padding.row` | number | `1` | Padding from top/bottom edge |
| `padding.col` | number | `2` | Padding from left/right edge |
| `custom_position` | function | `nil` | Custom position calculator function |

#### Recording Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `output_dir` | string | `"~/Videos/nvim-recordings"` | Directory for saving recordings |
| `auto_open` | boolean | `false` | Automatically open video after recording |
| `open_command` | string | `nil` | Custom command to open videos |

#### Keys Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_overlay` | boolean | `true` | Enable keystroke overlay |
| `max_repeat_count` | number | `3` | Keypress count before collapsing |
| `ignore_navigation` | boolean | `true` | Collapse navigation keys (hjkl, etc.) |
| `ignore_mouse` | boolean | `true` | Hide mouse events from overlay |
| `separator` | string | `"  ·  "` | Separator between keystrokes |

### Example Custom Configuration

```lua
require("rec").setup({
  overlay = {
    position = "top-center",
    max_keys = 10,
    opacity = 85,
    width = 40,
    height = 6,
  },
  recording = {
    output_dir = "~/Desktop/recordings",
    auto_open = true,
    open_command = "vlc",
  },
  keys = {
    show_overlay = true,
    max_repeat_count = 5,
    separator = " → ",
  },
})
```

## 🚀 Usage

### Commands

rec.nvim provides the following commands:

| Command | Description |
|---------|-------------|
| `:RecStart` | Start fullscreen recording |
| `:RecWin` | Record current window only (requires yabai) |
| `:RecStop` | Stop the current recording |
| `:RecPause` | Pause the current recording |
| `:RecResume` | Resume a paused recording |
| `:RecStatus` | Check recording status |
| `:RecDevices` | List available capture devices |
| `:RecOpen` | Open the latest recording |
| `:RecDashboard` | Toggle recordings dashboard |
| `:RecDebug` | Show debug information |
| `:RecCalibrate` | Show cell size calibration info |

### Example Key Mappings

Add these to your Neovim configuration:

```lua
-- Start/stop recording
vim.keymap.set("n", "<leader>rs", "<cmd>RecStart<cr>", { desc = "Start recording" })
vim.keymap.set("n", "<leader>rw", "<cmd>RecWin<cr>", { desc = "Record window" })
vim.keymap.set("n", "<leader>re", "<cmd>RecStop<cr>", { desc = "Stop recording" })

-- Pause/resume
vim.keymap.set("n", "<leader>rp", "<cmd>RecPause<cr>", { desc = "Pause recording" })
vim.keymap.set("n", "<leader>rr", "<cmd>RecResume<cr>", { desc = "Resume recording" })

-- View recordings
vim.keymap.set("n", "<leader>ro", "<cmd>RecOpen<cr>", { desc = "Open latest recording" })
vim.keymap.set("n", "<leader>rd", "<cmd>RecDashboard<cr>", { desc = "Recording dashboard" })
```

### Keystroke Symbol Reference

The overlay displays keys using Unicode symbols for better readability:

| Key | Symbol | Description |
|-----|--------|-------------|
| Enter | ⏎ | Return/Enter key |
| Escape | ⎋ | Escape key |
| Tab | ⇥ | Tab key |
| Space | ␣ | Space bar |
| Backspace | ⌫ | Backspace key |
| Delete | ⌦ | Delete key |
| Up | ↑ | Arrow up |
| Down | ↓ | Arrow down |
| Left | ← | Arrow left |
| Right | → | Arrow right |
| Home | ⇱ | Home key |
| End | ⇲ | End key |
| Page Up | ⇞ | Page up |
| Page Down | ⇟ | Page down |

#### Modifiers

| Modifier | Symbol | Description |
|----------|--------|-------------|
| Shift | ⇧ | Shift key |
| Control | ⌃ | Control key |
| Alt/Option | ⌥ | Alt or Option key |
| Command | ⌘ | Command/Meta key |

#### Examples

- `⌃c` - Control + C
- `⇧a` - Shift + A (capital A)
- `⌘s` - Command + S
- `⌃⇧p` - Control + Shift + P
- `j×5` - 'j' pressed 5 times (collapsed)

## 🔨 Building from Source

### Quick Build

```bash
cd crates/rec-cli
cargo build --release
```

The compiled binary will be at `crates/rec-cli/target/release/rec-cli`.

### Development Build

For faster compilation during development:

```bash
cd crates/rec-cli
cargo build
```

The binary will be at `crates/rec-cli/target/debug/rec-cli`.

### Cargo Commands

```bash
# Build with optimizations
cargo build --release

# Run tests
cargo test

# Check for errors without building
cargo check

# Clean build artifacts
cargo clean
```

## 📁 Project Structure

```
rec.nvim/
├── lua/
│   └── rec/
│       ├── init.lua          # Main plugin entry point
│       ├── config.lua        # Configuration management
│       ├── keys.lua          # Keystroke processing and symbols
│       ├── ui.lua            # UI components and windows
│       ├── cli.lua           # CLI backend interface
│       ├── geometry.lua      # Window geometry calculations
│       ├── storage.lua       # Recording metadata storage
│       ├── dashboard.lua     # Recording history dashboard
│       └── util.lua          # Utility functions
├── plugin/
│   └── rec.lua               # Plugin initialization and commands
├── crates/
│   └── rec-cli/
│       ├── src/
│       │   └── main.rs       # Rust CLI implementation
│       ├── Cargo.toml        # Rust dependencies
│       └── target/           # Build output (ignored)
├── .gitignore
└── README.md                 # This file
```

### Component Overview

- **lua/rec/init.lua** - Core plugin logic, recording state management, HUD/overlay windows
- **lua/rec/config.lua** - Configuration system with validation and defaults
- **lua/rec/keys.lua** - Keystroke capture, normalization, and symbol mapping
- **lua/rec/cli.lua** - Interface to the Rust CLI backend
- **lua/rec/geometry.lua** - Window geometry detection for window recording
- **lua/rec/storage.lua** - Recording metadata persistence
- **lua/rec/dashboard.lua** - UI for browsing recording history
- **crates/rec-cli/src/main.rs** - FFmpeg-based screen capture backend in Rust

## 🔧 Troubleshooting

### FFmpeg Not Found

**Error**: `ffmpeg failed to start (is it installed?)`

**Solution**: Install FFmpeg using Homebrew:
```bash
brew install ffmpeg
```

Verify installation:
```bash
ffmpeg -version
```

### Permission Denied

**Error**: `Screen Recording permission denied`

**Solution**: 
1. Open **System Settings** → **Privacy & Security** → **Screen Recording**
2. Enable screen recording permission for your terminal application
3. Restart your terminal
4. Restart Neovim

### CLI Not Executable

**Error**: `rec-cli not executable`

**Solution**: Make sure the CLI is built:
```bash
cd crates/rec-cli
cargo build --release
chmod +x target/release/rec-cli
```

### No Devices Found

**Error**: `No screen capture device found`

**Solution**: Check available devices:
```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

Update the `SCREEN_INDEX` constant in `crates/rec-cli/src/main.rs` to match your screen device index.

### Recording File Not Found

**Issue**: Video file doesn't appear after stopping recording

**Solution**: 
1. Check the output directory exists:
   ```bash
   ls -la ~/Videos/nvim-recordings
   ```
2. Run `:RecDebug` to see diagnostic information
3. Check FFmpeg logs:
   ```bash
   cat /tmp/rec.nvim.ffmpeg.log
   ```

### Window Recording Fails

**Issue**: `:RecWin` command fails or can't detect window

**Solution**: Window recording requires [yabai](https://github.com/koekeishiya/yabai):
```bash
brew install koekeishiya/formulae/yabai
```

Verify yabai is working:
```bash
yabai -m query --windows --window
```

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes** and test thoroughly
4. **Commit your changes**: `git commit -m 'Add amazing feature'`
5. **Push to the branch**: `git push origin feature/amazing-feature`
6. **Open a Pull Request**

### Development Guidelines

- Follow the existing code style
- Add tests for new features
- Update documentation as needed
- Test on macOS before submitting

### Reporting Issues

When reporting issues, please include:
- Neovim version (`:version`)
- macOS version
- FFmpeg version (`ffmpeg -version`)
- Rust version (`rustc --version`)
- Steps to reproduce
- Error messages or logs

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **[FFmpeg](https://ffmpeg.org/)** - The powerful multimedia framework powering the recording backend
- **[AVFoundation](https://developer.apple.com/av-foundation/)** - Apple's framework for screen capture
- **[screenkey](https://gitlab.com/screenkey/screenkey)** - Inspiration for keystroke overlay functionality
- **Neovim Community** - For the amazing plugin ecosystem

## 💬 Support

- 📖 **Documentation**: See this README and inline code documentation
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/willsantiagomedina/rec.nvim/issues)
- 💡 **Feature Requests**: [GitHub Issues](https://github.com/willsantiagomedina/rec.nvim/issues)
- 📧 **Contact**: santiagowill054@gmail.com

---

Made with ❤️ for the Neovim community
