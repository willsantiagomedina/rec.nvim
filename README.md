# rec.nvim

A Neovim plugin for screen recording with keystroke overlay, powered by ffmpeg.

## Overview

rec.nvim is a Neovim plugin that enables screen recording directly from your editor. It features a real-time HUD showing recording time and an optional keystroke overlay window to visualize your keypresses during recordings. The plugin uses a Rust-based CLI backend (`rec-cli`) for optimal performance and reliable ffmpeg process management.

## Features

- **Screen recording** - Record your screen directly from Neovim using ffmpeg
- **Real-time HUD** - Recording time display with elapsed time counter
- **Keystroke overlay** - Show keypresses in a floating window with customizable position and styling
- **Rust backend** - High-performance CLI backend (`rec-cli`) for ffmpeg process management
- **Configurable output** - Set custom output directory for your recordings
- **Auto-open recordings** - Optionally open recordings automatically after stopping
- **Customizable overlay positions** - Choose from bottom-right, bottom-center, top-right, top-center, or define custom positions
- **Smart keystroke filtering** - Filter navigation keys, mouse events, and collapse key repetitions for cleaner display

## Requirements

- Neovim >= 0.8.0
- ffmpeg installed on your system
- Rust toolchain (for building rec-cli)

### Installing ffmpeg

**macOS:**
```bash
brew install ffmpeg
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt install ffmpeg

# Arch Linux
sudo pacman -S ffmpeg
```

**Windows:**
Download from [ffmpeg.org](https://ffmpeg.org/download.html)

## Installation

### lazy.nvim

```lua
{
  "willsantiagomedina/rec.nvim",
  config = function()
    require("rec").setup({
      -- your configuration here (optional)
    })
  end,
}
```

### packer.nvim

```lua
use {
  "willsantiagomedina/rec.nvim",
  config = function()
    require("rec").setup({
      -- your configuration here (optional)
    })
  end,
}
```

### vim-plug

```vim
Plug 'willsantiagomedina/rec.nvim'

" In your init.vim or init.lua:
lua << EOF
require("rec").setup({
  -- your configuration here (optional)
})
EOF
```

## Building the Rust CLI Backend

After installing the plugin, you need to build the Rust CLI backend:

```bash
# Navigate to the plugin directory (path depends on your plugin manager):

# For lazy.nvim:
cd ~/.local/share/nvim/lazy/rec.nvim/crates/rec-cli

# For packer.nvim:
cd ~/.local/share/nvim/site/pack/packer/start/rec.nvim/crates/rec-cli

# For vim-plug (Neovim):
cd ~/.local/share/nvim/plugged/rec.nvim/crates/rec-cli

# For vim-plug (Vim):
cd ~/.vim/plugged/rec.nvim/crates/rec-cli

# Then build the CLI:
cargo build --release
```

The built binary will be at `target/release/rec-cli` (or `target/debug/rec-cli` for development builds).

> **Note**: You'll need to update the `BIN` path in `lua/rec/cli.lua` or `lua/rec/init.lua` to point to your compiled binary. For example:
> ```lua
> -- In lua/rec/cli.lua
> local BIN = vim.fn.expand("~/.local/share/nvim/lazy/rec.nvim/crates/rec-cli/target/release/rec-cli")
> ```

## Configuration

Here are the default configuration options:

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

## Setup Examples

### Basic Setup

Minimal configuration with defaults:

```lua
require("rec").setup()
```

### Advanced Setup

Customized configuration:

```lua
require("rec").setup({
  overlay = {
    position = "bottom-center",
    max_keys = 7,
    opacity = 85,
    width = 40,
    height = 6,
  },
  
  recording = {
    output_dir = "~/Documents/recordings",
    auto_open = true,
    open_command = "mpv", -- Use mpv to open recordings
  },
  
  keys = {
    show_overlay = true,
    max_repeat_count = 5,
    ignore_navigation = false,
    separator = " | ",
  },
})
```

### Custom Position Function

Define a custom position for the keystroke overlay:

```lua
require("rec").setup({
  overlay = {
    custom_position = function(config)
      -- Center in the screen
      return {
        anchor = "NW",
        row = math.floor(vim.o.lines / 2),
        col = math.floor(vim.o.columns / 2) - 16,
      }
    end,
  },
})
```

## Commands

rec.nvim provides the following user commands:

- `:RecStart` - Start recording your screen
- `:RecStop` - Stop the current recording
- `:RecOpen` - Open the latest recording in your default video player
- `:RecDevices` - List available recording devices (useful for troubleshooting)
- `:RecStatus` - Check if recording is currently active

## Usage

### Basic Workflow

1. **Start recording:**
   ```vim
   :RecStart
   ```
   A recording HUD will appear in the top-right corner showing elapsed time, and a keystroke overlay will appear at the configured position.

2. **Perform your actions in Neovim** - All your keystrokes will be captured in the overlay window.

3. **Stop recording:**
   ```vim
   :RecStop
   ```
   The recording will be saved to your configured output directory.

4. **Open the recording:**
   ```vim
   :RecOpen
   ```
   Or navigate to your output directory to find the recording.

### Example Recording Session

```vim
" Configure with auto-open
:lua require("rec").setup({ recording = { auto_open = true } })

" Start recording
:RecStart

" Do some editing...
" Press keys, navigate, edit code

" Stop recording (will auto-open the video)
:RecStop
```

## Architecture

rec.nvim uses a two-component architecture:

### Lua Plugin (Neovim Interface)

The Lua plugin provides:
- User commands and API
- Real-time HUD with recording timer
- Keystroke overlay with smart filtering
- Configuration management
- Integration with Neovim's UI system

### Rust CLI Backend (ffmpeg Process Management)

The Rust CLI backend (`rec-cli`) handles:
- ffmpeg process spawning and management
- Screen capture device detection
- Recording state management
- Signal handling for proper MP4 finalization
- Cross-platform compatibility

This separation allows for:
- **Reliability**: The Rust backend ensures ffmpeg processes are properly managed
- **Performance**: Low-overhead process management
- **Stability**: Independent process prevents Neovim crashes from affecting recordings

## Statusline Integration

You can integrate the recording status into your statusline:

### With lualine.nvim

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      function()
        return require('rec').status()
      end,
    },
  },
})
```

### Custom Statusline

```lua
-- In your statusline configuration
local rec_status = require('rec').status()
if rec_status ~= "" then
  -- Display rec_status in your statusline
end
```

The `status()` function returns:
- `"🔴 REC"` when recording is active
- `""` (empty string) when idle

## Troubleshooting

### Recording doesn't start

1. Check if ffmpeg is installed: `ffmpeg -version`
2. Verify the `rec-cli` binary is built and accessible
3. Check ffmpeg logs (location varies by platform):
   - **Linux/macOS**: `/tmp/rec.nvim.ffmpeg.log`
   - **Windows**: Check your temp directory or configure a custom log location
4. List available devices: `:RecDevices`

### Permission denied (macOS)

On macOS, you need to grant screen recording permission:
1. Open **System Settings → Privacy & Security → Screen Recording**
2. Add your terminal application to the allowed list
3. Restart your terminal

### Keystroke overlay not showing

Check that `keys.show_overlay` is set to `true` in your configuration:

```lua
require("rec").setup({
  keys = {
    show_overlay = true,
  },
})
```

## License

MIT License

Copyright (c) 2024 Will Santiago

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

## Author

**Will Santiago**

- GitHub: [@willsantiagomedina](https://github.com/willsantiagomedina)
- Email: santiagowill054@gmail.com

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

If you encounter issues or have questions:
- Open an issue on [GitHub](https://github.com/willsantiagomedina/rec.nvim/issues)
- Check the ffmpeg logs for recording errors:
  - **Linux/macOS**: `/tmp/rec.nvim.ffmpeg.log`
  - **Windows**: Check your system temp directory
