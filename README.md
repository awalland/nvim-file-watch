# nvim-file-watch

I got tired of reloading open files when vibing with my good friend claude,
so i asked him to write a neat little file-watch plugin, that would reload
open files if they got changed by him in the background.


Real-time file watching for Neovim using libuv's `fs_event` (inotify on Linux).

Automatically reloads files when they change on disk—even while Neovim is in the background. No polling required.

## Features

- **Real-time detection**: Uses OS-level file system events (inotify on Linux, FSEvents on macOS, etc.)
- **Works in background**: Detects changes even when Neovim doesn't have focus
- **Conflict handling**: If you have unsaved changes when a file is modified externally, Neovim's built-in conflict dialog appears
- **Debounced**: Prevents multiple reloads when editors write multiple events
- **Configurable**: Customize debounce timing, notifications, and ignore patterns

## Requirements

- Neovim 0.10+ (for `vim.uv` API)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "awalland/nvim-file-watch",
  opts = {},
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "awalland/nvim-file-watch",
  config = function()
    require("file-watch").setup()
  end,
}
```

### Manual

Clone to your pack directory:

```sh
git clone https://github.com/awalland/nvim-file-watch \
  ~/.local/share/nvim/site/pack/plugins/start/nvim-file-watch
```

Then call setup in your init.lua:

```lua
require("file-watch").setup()
```

## Configuration

```lua
require("file-watch").setup({
  -- Debounce delay in milliseconds (some editors trigger multiple write events)
  debounce_ms = 100,

  -- Show notification when file is reloaded
  notify = true,

  -- Notification level (vim.log.levels.INFO, WARN, ERROR, etc.)
  notify_level = vim.log.levels.INFO,

  -- File patterns to ignore (Lua patterns)
  ignore_patterns = { "%.git/", "%.swp$", "~$", "4913$" },

  -- Automatically start watching files when they're opened
  auto_enable = true,
})
```

## Commands

| Command             | Description                              |
|---------------------|------------------------------------------|
| `:FileWatchEnable`  | Enable file watching for all buffers     |
| `:FileWatchDisable` | Disable file watching                    |
| `:FileWatchToggle`  | Toggle file watching on/off              |
| `:FileWatchStatus`  | Show which files are being watched       |

## API

```lua
local fw = require("file-watch")

fw.enable()       -- Enable watching
fw.disable()      -- Disable watching
fw.toggle()       -- Toggle on/off
fw.status()       -- Returns status table
fw.print_status() -- Prints status to messages
```

## How It Works

1. When a file is opened in a buffer, we create a `vim.uv.new_fs_event()` watcher on that file path
2. The OS notifies us immediately when the file changes on disk
3. We debounce the event (default 100ms) to handle editors that write multiple events
4. We call `:checktime` on that buffer to trigger Neovim's reload mechanism
5. If the buffer has unsaved changes, Neovim shows its built-in conflict dialog

This approach is much more efficient than polling with timers, and works even when Neovim is completely in the background.

## Why Not Just Use `autoread`?

Neovim's `autoread` option only triggers when certain events happen (like `FocusGained` or `BufEnter`). If Neovim is sitting in the background, it won't detect changes until you switch back to it.

This plugin uses actual file system events to detect changes immediately, regardless of Neovim's focus state.

## License

MIT
