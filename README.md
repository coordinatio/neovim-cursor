# neovim-cursor

**BIG DISCLAIMER**: This is not a _real_ plugin in the `neovim` sense of a plugin. It's just a way to integrate `cursor-cli` into the `neovim` editor. So whenever you read that it's a "plugin" , just read it as "terminal integration" (or something like that).

A Neovim plugin to integrate the Cursor AI agent CLI directly into your editor. Toggle a terminal running the agent CLI
(`cursor-agent` or `cursor agent`) with a simple keybinding and send visual selections for AI assistance.

This was created using Cursor in ~20 minutes; it doesn't have to be perfect, just needs something to run the Cursor agent CLI like the agent inside Cursor.


## Features

- 🚀 Toggle a vertical split terminal running the Cursor agent CLI with `<A-->`
- 🖥️ **Fullscreen mode** — toggle agent in the current window with `<A-=>` (ideal for small screens)
- 🎛️ **Manage multiple AI agent sessions simultaneously**
- 🔍 **Fuzzy finder with live preview** (Telescope integration)
- ✏️ **Rename and organize** agent terminals for different tasks
- ⌨️ **Full terminal mode support** - manage agents without leaving the terminal
- 📝 Send visual selections and file paths to the Cursor agent
- 📎 Copy Cursor links quickly: `@file` (normal mode) or `@file:start-end` (visual mode)
- 📂 **Prompt history in Telescope** – browse `.nvim-cursor/history/` with Telescope
- 📄 **Last prompt buffer** – open or switch to the most recent prompt file
- 💾 Persistent terminal sessions (hide/show without restarting)
- ⚙️ Fully configurable (keybindings, split position, size, etc.)
- 🔑 **Passthrough mode** — send keys directly to TUI apps running inside the agent terminal (`<leader>i` for single key, double-press for continuous mode)
- 🎯 Written in pure Lua


## Requirements

- Neovim >= 0.11.0
- Cursor agent CLI available in your `PATH`:
  - Preferably `cursor-agent` (common on Linux, and avoids launching the GUI)
  - Or `cursor` with `cursor agent` support


## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "felixcuello/neovim-cursor",
  config = function()
    require("neovim-cursor").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "felixcuello/neovim-cursor",
  config = function()
    require("neovim-cursor").setup()
  end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'felixcuello/neovim-cursor'

lua << EOF
require("neovim-cursor").setup()
EOF
```

## Usage

### Quick Start

1. **Open/Toggle Agent**: Press `<A-->` in normal mode
   - First time: Creates your first agent terminal
   - After that: Toggles (show/hide) the last active agent
2. **Fullscreen Toggle**: Press `<A-=>` in normal mode
   - Shows agent in the current window (no split — ideal for small screens)
   - Press again to switch back to your file
3. **Create New Agent**: Press `<leader>an` to create additional agent terminals
4. **Create New Fullscreen Agent**: Press `<leader>aN` to create a new agent in fullscreen mode
5. **Send File to Fullscreen Agent**: Press `<leader>aE` to send the current file contents to the agent and force the agent window to fullscreen
6. **Switch Agents**: Press `<F6>` to open a fuzzy picker with live preview
7. **Rename Agent**: Press `<leader>ar` to rename the current agent terminal

### Multi-Terminal Management

Work with multiple AI agents simultaneously for different tasks:

#### From Normal Mode

| Keybinding | Action |
|------------|--------|
| `<A-->` | Smart toggle - create first agent or show last active (split) |
| `<A-=>` | Fullscreen toggle - show agent fullscreen or switch back to file |
| `<leader>an` | Create new agent terminal with custom prompt |
| `<leader>aN` | Create new agent terminal in fullscreen |
| `<F6>` | Select agent from fuzzy picker (with live preview) |
| `<leader>ar` | Rename current agent terminal |
| `<leader>ah` | Create new prompt file in `.nvim-cursor/history/` (timestamp in filename) |
| `<leader>ae` | Send current file contents to agent |
| `<leader>aE` | Send current file contents to agent (force fullscreen) |
| `<leader>aH` | Open prompt history directory in Telescope (requires telescope.nvim) |
| `<leader>al` | Open or switch to last prompt file from history |
| `<leader>ac` | Copy `@file` link to clipboard (paste into Cursor prompt) |
| `<leader>i` | Send next key directly to TUI app in agent terminal |
| `<leader>ii` | Toggle continuous passthrough mode (all keys go to TUI, Esc to exit) |

#### From Visual Mode

| Keybinding | Action |
|------------|--------|
| `<leader>ac` | Copy `@file:start-end` link to clipboard (paste into Cursor prompt) |

#### From Terminal Mode

When you're inside an agent terminal, you can manage agents without leaving:

| Keybinding | Action |
|------------|--------|
| `<A-->` | Exit terminal mode / hide agent window |
| `<A-=>` | Toggle fullscreen mode / exit terminal |
| `<F7>` | Create new agent terminal |
| `<F6>` | Select agent from fuzzy picker |
| `<F2>` | Rename current agent terminal |
| `<F12>` | Open or switch to last prompt file from history |
| `<leader>i` | Send next key directly to TUI app in agent terminal |
| `<leader>ii` | Toggle continuous passthrough mode (all keys go to TUI, Esc to exit) |

> **Note:** All terminal mode keybindings are configurable via `terminal_keybindings` option (see Configuration section).

### Passthrough Mode

When a TUI application (e.g. a text editor, file manager, or pager) is running inside the agent terminal, Neovim's normal-mode keybindings intercept keys before they reach the terminal. Passthrough mode lets you send keys directly to the TUI app.

**Single-key passthrough** (`<leader>i` by default):
1. Navigate to the agent terminal window in normal mode
2. Press `<leader>i`, then press any key — it is sent directly to the TUI app
3. You return to normal mode immediately after

**Continuous passthrough mode** (double the passthrough key — `<leader>ii` by default):
1. Press `<leader>ii` to enter passthrough mode — all keys are forwarded to the TUI app
2. The status line shows `-- PASS THROUGH (Esc to exit) --`
3. Press `Esc` to exit passthrough mode and return to normal mode

> **Tip:** This is useful for interacting with full-screen TUI tools (e.g. `vim`, `htop`, `lazygit`) running inside an agent terminal session.

#### Example Workflow

```
1. Press <A--> → Creates "Agent 1"
2. Ask: "Help me debug this authentication issue"
3. Press <F7> → Prompt appears
4. Type: "Review my database schema"
5. Now you have two agents running!
6. Press <F6> → Telescope shows both with live preview
7. Navigate and press Enter to switch
8. Press <F2> → Rename to "Auth Debug" and "Schema Review"
```

### Visual Mode

**Send code selections to your active agent:**

1. Select text in visual mode (v, V, or Ctrl-v)
2. Press `<A-->` to send via split, or `<A-=>` to send via fullscreen
3. The plugin will:
   - Toggle the agent terminal (show it in split or fullscreen)
   - Send the file path with line range (e.g., `@file.lua:10-20`)

Example:
```
@/path/to/your/file.lua:10-15
```

The agent will have context about which file and lines you're referring to.

**Copy link to clipboard (for pasting into a Cursor prompt elsewhere):**

1. Select lines in visual mode (V or Ctrl-v)
2. Press `<leader>ac`
3. The link `@path/to/file:start-end` is copied to the system clipboard
4. Switch to the buffer where you're composing a Cursor prompt and paste (Ctrl+V)

Use this when you want to reference a line range in a prompt without sending it to the agent terminal immediately.

In normal mode, press `<leader>ac` without selecting anything to copy `@path/to/file` (no line range).

### Prompt history workflow

Create a markdown file for a cursor-agent task and send it in one go:

1. **Create prompt file**: `:CursorAgentPromptNew` or `<leader>ah`
   - Creates `${CWD}/.nvim-cursor/history/` if needed
   - Opens a new file named like `2025-02-04_14-30-45.md` (date and time to the second)
2. **Write your prompt** in the opened buffer (what you want the agent to do).
3. **Send to agent**: `:CursorAgentPromptSend` or `<leader>ae`
   - Saves the buffer if modified
   - Shows/creates the agent terminal and sends the current buffer contents directly
   - If current buffer is a prompt file created by `<leader>ah`, it is closed with `:bd` semantics after successful send
   - If no file buffers remain, opens an empty buffer like `:new`

**Additional prompt history actions:**

- **Browse history in Telescope**: `:CursorAgentHistoryTelescope` or `<leader>aH`  
  Opens the prompt history directory in Telescope's file finder (requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)).
- **Open last prompt**: `:CursorAgentPromptLast` or `<leader>al`  
  Opens or switches to the buffer of the most recent prompt file (by timestamp in filename).

### Commands

The plugin provides comprehensive commands for all operations:

#### Terminal Management
- `:CursorAgent` - Toggle agent terminal (split mode)
- `:CursorAgentFullscreen` - Toggle agent terminal (fullscreen mode)
- `:CursorAgentNew [prompt]` - Create new agent terminal with optional initial prompt
- `:CursorAgentNewFullscreen` - Create new agent terminal in fullscreen
- `:CursorAgentSelect` - Open agent picker
- `:CursorAgentRename [name]` - Rename active agent (interactive if no argument)
- `:CursorAgentList` - List all agent terminals with status

#### Prompt history
- `:CursorAgentPromptNew` - Create new prompt file in `.nvim-cursor/history/` (timestamp in filename)
- `:CursorAgentPromptSend` - Send current file contents to the active agent terminal
- `:CursorAgentPromptSendFullscreen` - Send current file contents to the active agent terminal and force the agent window to fullscreen
- `:CursorAgentPromptSendNew` - Deprecated compatibility shim: create new agent and send current file contents
- `:CursorAgentHistoryTelescope` - Open prompt history directory in Telescope
- `:CursorAgentPromptLast` - Open or switch to last prompt file from history

#### Utilities
- `:CursorAgentCopyLink [range]` - Copy `@file:start-end` link to clipboard; use range (e.g. `:10,20CursorAgentCopyLink`) or current line (`@file:line-line`)
- `:CursorAgentSend <text>` - Send arbitrary text to active agent
- `:CursorAgentVersion` - Display plugin version

> **Note:** To close an agent terminal, simply type `exit` in the terminal or press `Ctrl+D`

## Configuration

### Default Configuration

```lua
require("neovim-cursor").setup({
  -- Multi-terminal keybindings (all configurable)
  keybindings = {
    toggle = "<A-->",                -- Toggle agent window in split (show last active)
    toggle_fullscreen = "<A-=>",     -- Toggle agent window fullscreen
    new = "<leader>an",              -- Create new agent terminal
    new_fullscreen = "<leader>aN",   -- Create new agent terminal in fullscreen
    select = "<F6>",                 -- Select agent terminal (fuzzy picker)
    rename = "<leader>ar",           -- Rename current agent terminal
    prompt_new = "<leader>ah",       -- Create new prompt file in .nvim-cursor/history
    prompt_send = "<leader>ae",      -- Send current file contents to agent
    prompt_send_fullscreen = "<leader>aE",  -- Send current file contents to agent (force fullscreen)
    prompt_history_telescope = "<leader>aH",  -- Open prompt history in Telescope
    prompt_last = "<leader>al",      -- Open or switch to last prompt buffer
    copy_link = "<leader>ac",        -- Copy link: normal mode => @file, visual mode => @file:start-end
  },

  history = {
    dir = ".nvim-cursor/history",  -- Relative to CWD
  },

  -- Terminal naming configuration
  terminal = {
    default_name = "Agent",      -- Default name prefix for terminals
    auto_number = true,          -- Auto-append numbers (Agent 1, Agent 2, etc.)
  },

  -- Terminal split configuration
  split = {
    position = "right",  -- "right", "left", "top", "bottom"
    size = 0.5,          -- 50% of editor width/height (0.0-1.0)
  },

  -- CLI command to run (string or array of strings)
  -- When an array is provided, a Telescope picker will appear when creating
  -- a new terminal, letting you choose which command to launch.
  command = "cursor agent",
  -- command = { "cursor agent", "claude", "aider" },  -- multiple commands

  -- Terminal callbacks (optional)
  term_opts = {
    on_open = function()
      -- Called when terminal opens
      print("Cursor agent started")
    end,
    on_close = function(exit_code)
      -- Called when terminal closes
      print("Cursor agent exited with code: " .. exit_code)
    end,
  },

  -- Terminal mode keybindings (when inside terminal buffer)
  terminal_keybindings = {
    hide = "<A-->",      -- Hide terminal window (terminal + normal mode in terminal)
    toggle_fullscreen = "<A-=>", -- Toggle fullscreen mode
    new = "<F7>",        -- Create new agent terminal
    rename = "<F2>",     -- Rename current agent terminal
    select = "<F6>",     -- Select agent terminal
    prompt_last = "<F12>", -- Open or switch to last prompt buffer
    passthrough = "<leader>i", -- Send next key (or enter passthrough mode) to TUI app
  },
})
```

> **Note (Linux / GUI launcher):** If `cursor-agent` is in your `PATH`, the plugin will automatically prefer it unless you explicitly set `command`.

### Custom Configuration Examples

#### Custom Keybindings

```lua
require("neovim-cursor").setup({
  keybindings = {
    toggle = "<C-a>",       -- Use Ctrl+a for toggle
    new = "<C-n>",          -- Use Ctrl+n for new terminal
    select = "<C-s>",       -- Use Ctrl+s for select
    rename = "<leader>rn",  -- Use <leader>rn for rename
    copy_link = "<leader>ac", -- Copy link: normal mode => @file, visual mode => @file:start-end (use "" to disable)
  },
})
```

#### Custom Terminal Names

```lua
require("neovim-cursor").setup({
  terminal = {
    default_name = "AI Assistant",  -- Custom prefix
    auto_number = true,              -- "AI Assistant 1", "AI Assistant 2", etc.
  },
})
```

#### Left Split with 40% Width

```lua
require("neovim-cursor").setup({
  split = {
    position = "left",
    size = 0.4,
  },
})
```

#### Custom Command with Arguments

```lua
require("neovim-cursor").setup({
  command = "cursor agent --model gpt-4",
})
```

#### Multiple Commands (Command Picker)

Pass an array of commands to get a Telescope picker every time a new terminal is created:

```lua
require("neovim-cursor").setup({
  command = { "cursor agent", "claude", "aider", "cursor-agent" },
})
```

When only a single command is configured (string or array of one), the picker is skipped.

#### Linux / `cursor-agent` binary

On some systems `cursor` launches the GUI app and the agent CLI is provided as `cursor-agent`.
If `cursor-agent` is in your `PATH`, the plugin will prefer it automatically. You can also
set it explicitly:

```lua
require("neovim-cursor").setup({
  command = "cursor-agent",
})
```

#### Custom Terminal Mode Keybindings

You can customize keybindings used when inside a terminal buffer:

```lua
require("neovim-cursor").setup({
  terminal_keybindings = {
    hide = "<C-h>",      -- Use Ctrl+h to hide terminal
    new = "<leader>n",   -- Use <leader>n for new terminal
    rename = "<leader>r", -- Use <leader>r for rename
    select = "<leader>t", -- Use <leader>t for select
    prompt_last = "<leader>l", -- Open or switch to last prompt buffer
    passthrough = "<leader>i", -- Send next key (or enter passthrough mode) to TUI app
  },
})
```

#### Backward Compatibility

The old `keybinding` option is still supported for backward compatibility:

```lua
require("neovim-cursor").setup({
  keybinding = "<A-->",  -- Still works, sets the toggle keybinding
})
```

## Advanced Usage

### Programmatic Access

You can access the terminal functions directly:

```lua
local cursor = require("neovim-cursor")

-- Access plugin version
print("Version: " .. cursor.version)

-- Toggle terminal
cursor.normal_mode_handler()

-- Create new terminal programmatically
cursor.new_terminal_handler()

-- Send text to active terminal
cursor.terminal.send_text("@myfile.lua\nExplain this code")

-- Check if terminal is running
local terminal_id = cursor.tabs.get_active()
if cursor.terminal.is_running(terminal_id) then
  print("Terminal is running")
end

-- List all terminals
local terminals = cursor.tabs.list_terminals()
for _, term in ipairs(terminals) do
  print(string.format("%s: %s", term.id, term.name))
end

-- Get terminal state (for debugging)
local state = cursor.tabs.get_state()
print(vim.inspect(state))
```

### Multi-Terminal API

```lua
local tabs = require("neovim-cursor.tabs")

-- Get active terminal ID
local active_id = tabs.get_active()

-- Get terminal metadata
local term = tabs.get_terminal(active_id)
print("Name: " .. term.name)
print("Created: " .. term.created_at)

-- Rename a terminal
tabs.rename_terminal(active_id, "New Name")

-- Delete a terminal
tabs.delete_terminal(active_id)

-- Check if any terminals exist
if tabs.has_terminals() then
  print("Terminals count: " .. tabs.count())
end
```

## Tips & Best Practices

### Organizing Your Agents

Use descriptive names to organize agents by task:
- **"Backend API"** - for backend code questions
- **"Frontend UI"** - for UI/UX implementation
- **"Debug Session"** - for troubleshooting
- **"Code Review"** - for reviewing pull requests
- **"Documentation"** - for writing docs

### Efficient Workflows

1. **Keep agents focused**: Create separate agents for different contexts instead of mixing topics in one
2. **Use terminal mode shortcuts**: Stay in terminal mode with `<F7>`, `<F6>`, `<F2>` for faster navigation
3. **Leverage the preview**: Use `<F6>` to preview conversations before switching
4. **Name early**: Rename agents as soon as you know their purpose with `<F2>`

### Telescope Integration

For the best experience, install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim). With Telescope you get:
- **Agent picker** (`<F6>`): live preview of agent conversations, fuzzy search by name, rename with `<F2>`
- **Prompt history** (`<leader>aH`): browse `.nvim-cursor/history/` with `find_files` in that directory

Without Telescope, the agent picker falls back to `vim.ui.select` (still functional, just less features). The prompt history command will show a warning if Telescope is not available.

## Troubleshooting

### Terminal doesn't open

- Ensure the Cursor agent CLI is installed and in your PATH
- Try running `cursor-agent` (preferred) or `cursor agent` manually in your terminal to verify it works
- Check for errors with `:messages`

### Keybinding doesn't work

- Make sure `<leader>` is set in your config (e.g., `vim.g.mapleader = " "`)
- Check for conflicting keybindings with `:verbose map <A-->`

### Visual selection not working

- Ensure you're pressing `<A-->` while still in visual mode
- The selection will be sent after the terminal opens/shows

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Related Projects

- [Cursor](https://cursor.sh/) - The AI-first code editor
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) - Terminal management for Neovim
- [vim-floaterm](https://github.com/voldikss/vim-floaterm) - Floating terminal plugin
