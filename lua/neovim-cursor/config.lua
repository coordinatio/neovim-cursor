-- Default configuration for neovim-cursor plugin
local M = {}

M.defaults = {
  -- Keybinding for toggling cursor agent (backward compatibility)
  keybinding = "<A-->",

  -- Multi-terminal keybindings
  keybindings = {
    toggle = "<A-->",                -- Toggle agent window in split (show last active)
    toggle_fullscreen = "<A-=>",     -- Toggle agent window fullscreen (show last active)
    new = "<leader>an",              -- Create new agent terminal
    new_fullscreen = "<leader>aN",   -- Create new agent terminal in fullscreen
    select = "<F6>",                 -- Select agent terminal (fuzzy picker)
    rename = "<leader>ar",           -- Rename current agent terminal
    prompt_new = "<leader>ah",       -- Create new prompt file in .nvim-cursor/history
    prompt_send = "<leader>ae",      -- Send current file contents to agent
    prompt_send_fullscreen = "<leader>aE",  -- Send current file contents to agent (force fullscreen)
    prompt_history_telescope = "<leader>aH",  -- Open prompt history dir in Telescope
    prompt_last = "<leader>al",      -- Open or switch to last prompt buffer
    copy_link = "<leader>ac",        -- Copy link (normal: @file, visual: @file:start-end) to unnamed register
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

  -- CLI command to run (string or array of strings)
  -- When an array is provided, a Telescope picker will appear when creating
  -- a new terminal, letting you choose which command to launch.
  command = "cursor agent",

  -- Terminal options
  term_opts = {
    on_open = nil,   -- Callback when terminal opens
    on_close = nil,  -- Callback when terminal closes
  },

  -- Terminal mode keybindings (when inside terminal buffer)
  terminal_keybindings = {
    hide = "<A-->",      -- Hide terminal window (terminal + normal mode in terminal)
    toggle_fullscreen = "<A-=>", -- Toggle fullscreen mode
    new = "<F7>",        -- Create new agent terminal
    rename = "<F2>",     -- Rename current agent window
    select = "<F6>",     -- Select agent terminal
    prompt_last = "<F12>", -- Open or switch to last prompt buffer
  },
}

-- Track whether we already warned about a removed/deprecated option,
-- so we only nag the user once per Neovim session.
local warned_keys = {}

local function warn_once(key, message)
  if warned_keys[key] then return end
  warned_keys[key] = true
  vim.schedule(function()
    vim.notify(message, vim.log.levels.WARN)
  end)
end

-- Deprecated options: tell the user once that their config still works,
-- but should be migrated.
local function check_deprecated_options(user_config)
  if not user_config or not user_config.keybindings then return end

  if user_config.keybindings.prompt_send_new ~= nil then
    warn_once("prompt_send_new",
      "[neovim-cursor] `keybindings.prompt_send_new` is deprecated but still supported. " ..
      "The default <leader>aE slot is now used by `keybindings.prompt_send_fullscreen`; " ..
      "create a new agent first, then use `keybindings.prompt_send` (or `keybindings.prompt_send_fullscreen`)."
    )
  end
end

-- Merge user config with defaults
-- Maintains backward compatibility with old 'keybinding' option.
function M.setup(user_config)
  user_config = user_config or {}

  check_deprecated_options(user_config)

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

function M.resolve_command(command, config)
  if command then return command end
  if type(config.command) == "string" then return config.command end
  if type(config.command) == "table" and #config.command > 0 then return config.command[1] end
  return "cursor agent"
end

function M.resolve_commands(config)
  local cmd = config.command
  if type(cmd) == "table" then
    return cmd
  end
  if type(cmd) == "string" then
    return { cmd }
  end
  return { "cursor agent" }
end

return M
