-- Default configuration for neovim-cursor plugin
local M = {}

M.defaults = {
  -- Keybinding for toggling cursor agent (backward compatibility)
  keybinding = "<leader>ai",

  -- Multi-terminal keybindings
  keybindings = {
    toggle = "<leader>ai",      -- Toggle agent window (show last active)
    new = "<leader>an",          -- Create new agent terminal
    select = "<leader>at",       -- Select agent terminal (fuzzy picker)
    rename = "<leader>ar",       -- Rename current agent terminal
    prompt_new = "<leader>ah",   -- Create new prompt file in .nvim-cursor/history
    prompt_send = "<leader>ae",  -- Send current file to agent with "Complete the task..."
    copy_link = "<leader>ac",    -- Copy @file:start-end link to clipboard (for Cursor prompt)
  },

  -- Prompt history (md files for cursor-agent tasks)
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
    position = "right",  -- right, left, top, bottom
    size = 0.5,          -- 50% of editor width/height
  },

  -- CLI command to run
  command = "cursor agent",

  -- Terminal options
  term_opts = {
    on_open = nil,   -- Callback when terminal opens
    on_close = nil,  -- Callback when terminal closes
  },

  -- Terminal mode keybindings (when inside terminal buffer)
  terminal_keybindings = {
    hide = "<Esc>",      -- Hide terminal window (terminal + normal mode in terminal)
    new = "<C-n>",       -- Create new agent terminal
    rename = "<C-r>",    -- Rename current agent window
    select = "<C-t>",    -- Select agent terminal
  },
}

-- Merge user config with defaults
-- Maintains backward compatibility with old 'keybinding' option
function M.setup(user_config)
  user_config = user_config or {}
  
  -- Backward compatibility: if old 'keybinding' provided but not 'keybindings', migrate it
  if user_config.keybinding and not user_config.keybindings then
    user_config.keybindings = {
      toggle = user_config.keybinding,
    }
  end
  
  local cfg = vim.tbl_deep_extend("force", M.defaults, user_config)

  -- If the user didn't explicitly set a command, prefer the dedicated CLI binary
  -- when it exists (common packaging: GUI launcher is `cursor`, CLI is `cursor-agent`).
  if user_config.command == nil and vim.fn.executable("cursor-agent") == 1 then
    cfg.command = "cursor-agent"
  end

  return cfg
end

return M

