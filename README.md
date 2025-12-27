# nvim-file-watch

I got tired of reloading open files when vibing with my good friend claude,
so i asked him to write a neat little file-watch plugin for neovim, that would reload
open files if they got changed by him in the background.

I have only tested this on my linux machine, i have no idea if it works anywhere else.


Real-time file watching for Neovim using libuv's `fs_event` (inotify on Linux).

Automatically reloads files when they change on disk—even while Neovim is in the background. No polling required.

## Features

- **Real-time detection**: Uses OS-level file system events (inotify on Linux, FSEvents on macOS, etc.)
- **Works in background**: Detects changes even when Neovim doesn't have focus
- **Conflict handling**: If you have unsaved changes when a file is modified externally, Neovim's built-in conflict dialog appears
- **Debounced**: Prevents multiple reloads when editors write multiple events
- **Configurable**: Customize debounce timing, notifications, and ignore patterns


## Demo
[![Demo](https://img.youtube.com/vi/9m9Cd2qpoDU/maxresdefault.jpg)](https://www.youtube.com/watch?v=9m9Cd2qpoDU)

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
  debounce_ms = 100,
  notify = true,
  notify_level = vim.log.levels.INFO,
  ignore_patterns = { "%.git/", "%.swp$", "~$", "4913$" },
  auto_enable = true,
})
```

### Options

#### `debounce_ms`
- **Type:** `number`
- **Default:** `100`

Delay in milliseconds before reloading a file after a change is detected. Many editors (including Neovim itself) trigger multiple file system events when saving a file. The debounce prevents multiple reloads from these rapid successive events. Increase this value if you notice duplicate reload notifications.

#### `notify`
- **Type:** `boolean`
- **Default:** `true`

Whether to show notifications when files are reloaded, deleted, or when watching is enabled/disabled. Set to `false` for silent operation.

#### `notify_level`
- **Type:** `number`
- **Default:** `vim.log.levels.INFO`

The notification level used for reload messages. Valid values are:
- `vim.log.levels.DEBUG`
- `vim.log.levels.INFO`
- `vim.log.levels.WARN`
- `vim.log.levels.ERROR`

This affects how notifications are styled and whether they appear based on your `vim.notify` configuration.

#### `ignore_patterns`
- **Type:** `string[]`
- **Default:** `{ "%.git/", "%.swp$", "~$", "4913$" }`

List of Lua patterns for file paths that should not be watched. Files matching any of these patterns will be ignored. The default patterns exclude:
- `%.git/` — Git internal files
- `%.swp$` — Vim swap files
- `~$` — Backup files ending with tilde
- `4913$` — Vim's test file used to check write permissions

Note: These are [Lua patterns](https://www.lua.org/pil/20.2.html), not glob patterns. Use `%.` to match a literal dot.

#### `auto_enable`
- **Type:** `boolean`
- **Default:** `true`

When `true`, file watching starts automatically when `setup()` is called and new files are watched as they're opened. Set to `false` if you want to manually control when watching is active using `:FileWatchEnable`.

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
