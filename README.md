# rec.nvim 🎥

A native screen recording solution for Neovim with floating window timer and statusline integration.

<div align="center">

**Start and stop screen recording directly from Neovim**

🔴 Visual recording indicator • ⏱️ Real-time timer • 🎯 Statusline integration

</div>

---

## ✨ Features

- **🎬 Native Recording**: Start and stop screen recording without leaving Neovim
- **⏱️ Floating Timer**: Beautiful floating window showing elapsed time in MM:SS format
- **🔴 Visual Indicator**: Clear "🔴 REC" indicator so you never forget you're recording
- **📊 Statusline Integration**: Display recording status in your statusline
- **⚡ Simple Commands**: Easy-to-use `:RecStart` and `:RecStop` commands
- **🦀 Rust Backend**: Fast and efficient Rust CLI powered by FFmpeg
- **🍎 macOS Support**: Native macOS screen recording with proper permissions handling

---

## 📋 Requirements

Before installing rec.nvim, ensure you have:

- **Neovim** (recent version with Lua support)
- **FFmpeg** installed on your system
- **macOS** (currently macOS-only due to AVFoundation usage)
- **Rust toolchain** (for building the backend CLI)

### Installing FFmpeg

```bash
# macOS (using Homebrew)
brew install ffmpeg
```

### Installing Rust

If you don't have Rust installed:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

---

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "willsantiagomedina/rec.nvim",
  build = "cd crates/rec-cli && cargo build --release",
  config = function()
    -- Optional: Add to your statusline
    -- require('lualine').setup {
    --   sections = {
    --     lualine_x = { function() return require('rec.cli').status() end }
    --   }
    -- }
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'willsantiagomedina/rec.nvim',
  run = 'cd crates/rec-cli && cargo build --release'
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'willsantiagomedina/rec.nvim', { 'do': 'cd crates/rec-cli && cargo build --release' }
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/willsantiagomedina/rec.nvim.git ~/.config/nvim/pack/plugins/start/rec.nvim
   ```

2. Build the Rust backend:
   ```bash
   cd ~/.config/nvim/pack/plugins/start/rec.nvim/crates/rec-cli
   cargo build --release
   ```

3. Update the binary path in `lua/rec/cli.lua`:
   ```lua
   -- Update this line to match your installation path
   local BIN = vim.fn.expand("~/.config/nvim/pack/plugins/start/rec.nvim/crates/rec-cli/target/release/rec-cli")
   ```

---

## ⚙️ Configuration

### Basic Setup

rec.nvim works out of the box with no configuration needed! Just install and use the commands.

### Statusline Integration

To show recording status in your statusline, add this to your statusline configuration:

**With lualine.nvim:**
```lua
require('lualine').setup {
  sections = {
    lualine_x = { 
      function() 
        local rec = require('rec.init')
        -- Returns "🔴 REC" when recording, empty string otherwise
        return rec.status()
      end 
    }
  }
}
```

### Custom Output Path

By default, recordings are saved to `~/Movies/rec.nvim.mp4` (or `~/rec.nvim.mp4` if Movies folder doesn't exist).

To customize the output path, you can modify the CLI backend or pass a custom path when starting recording.

---

## 🚀 Usage

### Commands

rec.nvim provides four main commands:

| Command | Description |
|---------|-------------|
| `:RecStart` | Start screen recording |
| `:RecStop` | Stop recording and save video |
| `:RecStatus` | Check if recording is active |
| `:RecDevices` | List available screen capture devices |

### Basic Workflow

1. **Start Recording**
   ```vim
   :RecStart
   ```
   A floating window appears in the top-right corner showing:
   ```
   🔴 REC
   00:00
   ```

2. **Recording in Progress**
   - The timer updates every second
   - The floating window stays visible while recording
   - Your statusline (if configured) shows the recording indicator

3. **Stop Recording**
   ```vim
   :RecStop
   ```
   - Recording stops
   - Video is saved to `~/Movies/rec.nvim.mp4`
   - Floating window closes
   - You'll see a notification with the save location

### Key Bindings (Optional)

Add these to your Neovim config for quick access:

```lua
-- In your init.lua or keymaps configuration
vim.keymap.set('n', '<leader>rs', ':RecStart<CR>', { desc = 'Start recording' })
vim.keymap.set('n', '<leader>rq', ':RecStop<CR>', { desc = 'Stop recording' })
```

---

## 🍎 macOS Permissions Setup

rec.nvim requires **Screen Recording** permission on macOS.

### First-Time Setup

1. The first time you run `:RecStart`, macOS will prompt for Screen Recording permission
2. Grant permission when prompted
3. **Important**: You must restart your terminal/Neovim after granting permission

### Manual Permission Setup

If you need to enable permissions manually:

1. Open **System Settings** (or System Preferences on older macOS)
2. Go to **Privacy & Security** → **Screen Recording**
3. Find your terminal application (Terminal.app, iTerm2, Alacritty, etc.)
4. Enable the checkbox next to it
5. Restart your terminal application

### Checking Devices

To see which screen devices are available:

```vim
:RecDevices
```

This will list available capture devices like:
```
[AVFoundation indev @ 0x...] Capture screen 0
[AVFoundation indev @ 0x...] Capture screen 1
```

The default is usually screen 0.

---

## 🛠️ Troubleshooting

### Recording doesn't start

**Problem**: You run `:RecStart` but nothing happens or you get an error.

**Solutions**:
1. Check FFmpeg is installed: `ffmpeg -version`
2. Verify Screen Recording permissions (see above)
3. Check the FFmpeg log: `cat /tmp/rec.nvim.ffmpeg.log`
4. Restart your terminal after granting permissions

### "Permission denied" error

**Problem**: Error message about screen recording permission denied.

**Solution**:
1. Enable Screen Recording permission in System Settings
2. **Restart your terminal application completely**
3. Try `:RecStart` again

### Video file is empty or doesn't exist

**Problem**: Recording stops but no video file is created.

**Solutions**:
1. Check the FFmpeg log: `cat /tmp/rec.nvim.ffmpeg.log`
2. Verify you have write permissions to `~/Movies/`
3. Make sure FFmpeg didn't crash (check system resources)
4. Run `:RecDevices` to verify the screen device index

### "Already recording" error

**Problem**: You get an error saying recording is already in progress.

**Solution**:
1. Run `:RecStatus` to check current status
2. If stuck, manually kill the process:
   ```bash
   kill $(cat /tmp/rec.nvim.pid)
   rm /tmp/rec.nvim.pid
   ```

### Binary not found

**Problem**: Error about `rec-cli` not being executable.

**Solution**:
1. Verify the CLI was built:
   ```bash
   ls -la crates/rec-cli/target/release/rec-cli
   ```
2. If not found, rebuild:
   ```bash
   cd crates/rec-cli
   cargo build --release
   ```
3. Update the binary path in `lua/rec/cli.lua`

---

## 📁 Project Structure

```
rec.nvim/
├── lua/
│   └── rec/
│       ├── init.lua       # Main plugin logic (recording state, UI)
│       ├── cli.lua        # Backend CLI communication layer
│       ├── config.lua     # Configuration (currently minimal)
│       ├── ui.lua         # UI components
│       ├── util.lua       # Utility functions
│       └── keys.lua       # Key mappings
├── plugin/
│   └── rec.lua           # Plugin initialization and commands
├── crates/
│   └── rec-cli/          # Rust CLI backend
│       ├── src/
│       │   └── main.rs   # FFmpeg wrapper and process management
│       ├── Cargo.toml
│       └── target/       # Compiled binaries
└── README.md
```

### How It Works

1. **Neovim Layer** (`lua/rec/`): Manages UI, state, and user commands
2. **CLI Backend** (`crates/rec-cli/`): Handles FFmpeg process management
3. **Communication**: The Lua layer calls the Rust CLI which manages FFmpeg
4. **Output**: Videos are encoded using FFmpeg's AVFoundation input and saved as MP4

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

1. Clone the repository
2. Build the CLI: `cd crates/rec-cli && cargo build`
3. Make your changes
4. Test thoroughly
5. Submit a PR

---

## 📝 License

MIT License - see the repository for details

---

## 🙏 Acknowledgments

- Built with ❤️ for the Neovim community
- Powered by [FFmpeg](https://ffmpeg.org/)
- Written in Lua and Rust

---

<div align="center">

**⭐ If you find rec.nvim useful, consider giving it a star! ⭐**

Made with 🦀 and ☕ by [Will Santiago](https://github.com/willsantiagomedina)

</div>
