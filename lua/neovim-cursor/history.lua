-- Prompt history workflow for neovim-cursor plugin
--
-- Provides:
-- - Creating a new markdown file in ${CWD}/.nvim-cursor/history/ with timestamp in filename
-- - Sending the current file to cursor-agent as @path + "Complete the task described in this file."
--
local M = {}

-- Create history directory path (relative to CWD)
local function history_dir_path(config)
  local cwd = vim.fn.getcwd()
  local dir = (config.history and config.history.dir) or ".nvim-cursor/history"
  if dir:match("^/") then
    return dir
  end
  return cwd .. "/" .. dir:gsub("/$", "")
end

-- Human-readable timestamp for filename: 2025-02-04_14-30-45
local function timestamp_filename()
  return os.date("%Y-%m-%d_%H-%M-%S") .. ".md"
end

-- Create a new prompt file in history dir and open it in the current window
-- @param config Plugin config (must have history.dir)
function M.create_prompt_file(config)
  config = config or {}
  local dir = history_dir_path(config)
  vim.fn.mkdir(dir, "p")
  local filename = timestamp_filename()
  local fullpath = dir .. "/" .. filename
  vim.cmd("edit " .. vim.fn.fnameescape(fullpath))
  vim.notify("Created " .. fullpath, vim.log.levels.INFO)
end

-- Send current buffer's file to cursor-agent: @path + "Complete the task described in this file."
-- Ensures at least one terminal exists and shows it, then sends the text.
-- Saves the current buffer if modified so the file exists on disk for the agent.
-- @param config Plugin config (for terminal/tabs)
function M.send_prompt_file_to_agent(config)
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == nil or path == "" then
    vim.notify("Current buffer has no file path (save the file first)", vim.log.levels.WARN)
    return
  end
  if vim.bo[buf].modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("write")
    end)
  end

  local terminal = require("neovim-cursor.terminal")
  local tabs = require("neovim-cursor.tabs")

  if not tabs.has_terminals() then
    tabs.create_terminal(nil, config)
  else
    local last_id = tabs.get_last()
    if last_id then
      terminal.toggle(config, last_id)
    else
      tabs.create_terminal(nil, config)
    end
  end

  local text_to_send = "@" .. path .. "\nComplete the task described in this file.\n"
  vim.defer_fn(function()
    local active_id = tabs.get_active()
    if active_id and terminal.is_running(active_id) then
      terminal.send_text(text_to_send, active_id)
      vim.notify("Sent prompt file to agent", vim.log.levels.INFO)
    end
  end, 100)
end

return M
