# neovim-cursor

**BIG DISCLAIMER**: This is not a _real_ plugin in the `neovim` sense of a plugin. It's just a way to integrate `cursor-cli` into the `neovim` editor. So whenever you read that it's a "plugin" , just read it as "terminal integration" (or something like that).

A Neovim plugin to integrate the Cursor AI agent CLI directly into your editor. Toggle a terminal running the agent CLI
(`cursor-agent` or `cursor agent`) with a simple keybinding and send visual selections for AI assistance.

This was created using Cursor in ~20 minutes; it doesn't have to be perfect, just needs something to run the Cursor agent CLI like the agent inside Cursor.


## Features

- 🚀 Toggle a vertical split terminal running the Cursor agent CLI with `<leader>ai`
- 🎛️ **Manage multiple AI agent sessions simultaneously**
- 🔍 **Fuzzy finder with live preview** (Telescope integration)
- ✏️ **Rename and organize** agent terminals for different tasks
- ⌨️ **Full terminal mode support** - manage agents without leaving the terminal
- 📝 Send visual selections and file paths to the Cursor agent
- 📎 Copy `@file:start-end` link to clipboard for pasting into Cursor prompts
- 📂 **Prompt history in Telescope** – browse `.nvim-cursor/history/` with Telescope
- 📄 **Last prompt buffer** – open or switch to the most recent prompt file
- 🆕 **Send to new agent** – send current file to a fresh agent (like new + prompt_send)
- 💾 Persistent terminal sessions (hide/show without restarting)
- ⚙️ Fully configurable (keybindings, split position, size, etc.)
- 🎯 Written in pure Lua


## Requirements

- Neovim >= 0.8.0
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

1. **Open/Toggle Agent**: Press `<leader>ai` in normal mode
   - First time: Creates your first agent terminal
   - After that: Toggles (show/hide) the last active agent
2. **Create New Agent**: Press `<leader>an` to create additional agent terminals
3. **Switch Agents**: Press `<leader>at` to open a fuzzy picker with live preview
4. **Rename Agent**: Press `<leader>ar` to rename the current agent terminal

### Multi-Terminal Management

Work with multiple AI agents simultaneously for different tasks:

#### From Normal Mode

| Keybinding | Action |
|------------|--------|
| `<leader>ai` | Smart toggle - create first agent or show last active |
| `<leader>an` | Create new agent terminal with custom prompt |
| `<leader>at` | Select agent from fuzzy picker (with live preview) |
| `<leader>ar` | Rename current agent terminal |
| `<leader>ah` | Create new prompt file in `.nvim-cursor/history/` (timestamp in filename) |
| `<leader>ae` | Send current file to agent: `@path` + "Complete the task described in this file." |
| `<leader>aE` | Send current file to a **new** agent (create new instance + send task) |
| `<leader>aH` | Open prompt history directory in Telescope (requires telescope.nvim) |
| `<leader>al` | Open or switch to last prompt file from history |

#### From Visual Mode

| Keybinding | Action |
|------------|--------|
| `<leader>ac` | Copy `@file:start-end` link to clipboard (paste into Cursor prompt) |

#### From Terminal Mode

When you're inside an agent terminal, you can manage agents without leaving:

| Keybinding | Action |
|------------|--------|
| `<Esc>` | Exit terminal mode / hide agent window |
| `<C-n>` | Create new agent terminal |
| `<C-t>` | Select agent from fuzzy picker |
| `<C-r>` | Rename current agent terminal |

> **Note:** All terminal mode keybindings are configurable via `terminal_keybindings` option (see Configuration section).

#### Example Workflow

```
1. Press <leader>ai → Creates "Agent 1"
2. Ask: "Help me debug this authentication issue"
3. Press <C-n> → Prompt appears
4. Type: "Review my database schema"
5. Now you have two agents running!
6. Press <C-t> → Telescope shows both with live preview
7. Navigate and press Enter to switch
8. Press <C-r> → Rename to "Auth Debug" and "Schema Review"
```

### Visual Mode

**Send code selections to your active agent:**

1. Select text in visual mode (v, V, or Ctrl-v)
2. Press `<leader>ai`
3. The plugin will:
   - Toggle the agent terminal (show it)
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

### Prompt history workflow

Create a markdown file for a cursor-agent task and send it in one go:

1. **Create prompt file**: `:CursorAgentPromptNew` or `<leader>ah`
   - Creates `${CWD}/.nvim-cursor/history/` if needed
   - Opens a new file named like `2025-02-04_14-30-45.md` (date and time to the second)
2. **Write your prompt** in the opened buffer (what you want the agent to do).
3. **Send to agent**: `:CursorAgentPromptSend` or `<leader>ae`
   - Saves the buffer if modified
   - Shows/creates the agent terminal and sends: `@<path>\nComplete the task described in this file.\n`

**Additional prompt history actions:**

- **Browse history in Telescope**: `:CursorAgentHistoryTelescope` or `<leader>aH`  
  Opens the prompt history directory in Telescope’s file finder (requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)).
- **Open last prompt**: `:CursorAgentPromptLast` or `<leader>al`  
  Opens or switches to the buffer of the most recent prompt file (by timestamp in filename).
- **Send to new agent**: `:CursorAgentPromptSendNew` or `<leader>aE`  
  Same as prompt_send but creates a new agent terminal first (like `CursorAgentNew`), then sends the current file.

### Commands

The plugin provides comprehensive commands for all operations:

#### Terminal Management
- `:CursorAgent` - Toggle agent terminal (smart toggle)
- `:CursorAgentNew [prompt]` - Create new agent terminal with optional initial prompt
- `:CursorAgentSelect` - Open agent picker
- `:CursorAgentRename [name]` - Rename active agent (interactive if no argument)
- `:CursorAgentList` - List all agent terminals with status

#### Prompt history
- `:CursorAgentPromptNew` - Create new prompt file in `.nvim-cursor/history/` (timestamp in filename)
- `:CursorAgentPromptSend` - Send current file to agent: `@path` + "Complete the task described in this file."
- `:CursorAgentPromptSendNew` - Create new agent and send current file (like new + prompt_send)
- `:CursorAgentHistoryTelescope` - Open prompt history directory in Telescope
- `:CursorAgentPromptLast` - Open or switch to last prompt file from history

#### Utilities
- `:CursorAgentCopyLink [range]` - Copy `@file:start-end` link to clipboard; use range (e.g. `:10,20CursorAgentCopyLink`) or current line
- `:CursorAgentSend <text>` - Send arbitrary text to active agent
- `:CursorAgentVersion` - Display plugin version

> **Note:** To close an agent terminal, simply type `exit` in the terminal or press `Ctrl+D`

## Configuration

### Default Configuration

```lua
require("neovim-cursor").setup({
  -- Multi-terminal keybindings (all configurable)
  keybindings = {
    toggle = "<leader>ai",           -- Toggle agent window (show last active)
    new = "<leader>an",              -- Create new agent terminal
    select = "<leader>at",           -- Select agent terminal (fuzzy picker)
    rename = "<leader>ar",           -- Rename current agent terminal
    prompt_new = "<leader>ah",       -- Create new prompt file in .nvim-cursor/history
    prompt_send = "<leader>ae",      -- Send current file to agent (complete task in file)
    prompt_send_new = "<leader>aE",  -- Send current file to a new agent
    prompt_history_telescope = "<leader>aH",  -- Open prompt history in Telescope
    prompt_last = "<leader>al",      -- Open or switch to last prompt buffer
    copy_link = "<leader>ac",        -- Copy @file:start-end link to unnamed register (visual mode)
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

  -- CLI command to run
  command = "cursor agent",

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
    hide = "<Esc>",      -- Hide terminal window (terminal + normal mode in terminal)
    new = "<C-n>",       -- Create new agent terminal
    rename = "<C-r>",    -- Rename current agent terminal
    select = "<C-t>",    -- Select agent terminal
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
    copy_link = "<leader>ac", -- Copy link in visual mode (use "" to disable)
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
  },
})
```

#### Backward Compatibility

The old `keybinding` option is still supported for backward compatibility:

```lua
require("neovim-cursor").setup({
  keybinding = "<leader>ai",  -- Still works, sets the toggle keybinding
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
2. **Use terminal mode shortcuts**: Stay in terminal mode with `<C-n>`, `<C-t>`, `<C-r>` for faster navigation
3. **Leverage the preview**: Use `<C-t>` to preview conversations before switching
4. **Name early**: Rename agents as soon as you know their purpose with `<C-r>`

### Telescope Integration

For the best experience, install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim). With Telescope you get:
- **Agent picker** (`<leader>at`): live preview of agent conversations, fuzzy search by name, rename with `<C-r>`
- **Prompt history** (`<leader>aH`): browse `.nvim-cursor/history/` with `find_files` in that directory

Without Telescope, the agent picker falls back to `vim.ui.select` (still functional, just less features). The prompt history command will show a warning if Telescope is not available.

## Troubleshooting

### Terminal doesn't open

- Ensure the Cursor agent CLI is installed and in your PATH
- Try running `cursor-agent` (preferred) or `cursor agent` manually in your terminal to verify it works
- Check for errors with `:messages`

### Keybinding doesn't work

- Make sure `<leader>` is set in your config (e.g., `vim.g.mapleader = " "`)
- Check for conflicting keybindings with `:verbose map <leader>ai`

### Visual selection not working

- Ensure you're pressing `<leader>ai` while still in visual mode
- The selection will be sent after the terminal opens/shows

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Related Projects

- [Cursor](https://cursor.sh/) - The AI-first code editor
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) - Terminal management for Neovim
- [vim-floaterm](https://github.com/voldikss/vim-floaterm) - Floating terminal plugin
