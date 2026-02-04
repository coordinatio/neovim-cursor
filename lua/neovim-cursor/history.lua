-- Prompt history workflow for neovim-cursor plugin
--
-- Provides:
-- - Creating a new markdown file in ${CWD}/.nvim-cursor/history/ with timestamp in filename
-- - Sending the current file to cursor-agent as @path + "Complete the task described in this file."
--
local M = {}

-- Create history directory path (relative to CWD)
local function history_dir_path(cfg)
  local cwd = vim.fn.getcwd()
  local dir = (cfg and cfg.history and cfg.history.dir) or ".nvim-cursor/history"
  if dir:match("^/") then
    return dir
  end
  return cwd .. "/" .. dir:gsub("/$", "")
end

-- Expose history dir path for other modules
function M.history_dir_path(config)
  return history_dir_path(config)
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

-- Return full path of the most recent prompt file in history (by timestamp in filename).
-- Returns nil if directory does not exist or has no .md files.
function M.get_last_prompt_file(config)
  config = config or {}
  local dir = history_dir_path(config)
  if vim.fn.isdirectory(dir) ~= 1 then
    return nil
  end
  local files = vim.fn.readdir(dir)
  local md_files = {}
  for _, f in ipairs(files) do
    if f:match("%.md$") then
      table.insert(md_files, f)
    end
  end
  if #md_files == 0 then
    return nil
  end
  table.sort(md_files, function(a, b)
    return a > b
  end)
  return dir .. "/" .. md_files[1]
end

-- Open history directory in Telescope (find_files with cwd = history dir).
-- No-op with a warning if Telescope is not available.
function M.open_history_in_telescope(config)
  local ok, builtin = pcall(require, "telescope.builtin")
  if not ok then
    vim.notify("telescope.nvim is required for CursorAgentHistoryTelescope", vim.log.levels.WARN)
    return
  end
  local dir = history_dir_path(config)
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.fn.mkdir(dir, "p")
  end
  builtin.find_files({
    cwd = dir,
    prompt_title = "Prompt history",
  })
end

-- Open or switch to the buffer of the last prompt file from history.
function M.open_last_prompt_buffer(config)
  local path = M.get_last_prompt_file(config)
  if not path then
    vim.notify("No prompt files in history", vim.log.levels.WARN)
    return
  end
  local buf = vim.fn.bufadd(path)
  if vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_set_current_buf(buf)
  else
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end
end

-- Like send_prompt_file_to_agent but creates a new cursor-agent instance (like CursorAgentNew).
function M.send_prompt_file_to_new_agent(config)
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

  tabs.create_terminal(nil, config)

  local text_to_send = "@" .. path .. "\nComplete the task described in this file.\n"
  vim.defer_fn(function()
    local active_id = tabs.get_active()
    if active_id and terminal.is_running(active_id) then
      terminal.send_text(text_to_send, active_id)
      vim.notify("Sent prompt file to new agent", vim.log.levels.INFO)
    end
  end, 100)
end

return M
