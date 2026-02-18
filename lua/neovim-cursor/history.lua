-- Prompt history workflow for neovim-cursor plugin
--
-- Provides:
-- - Creating a new markdown file in ${CWD}/.nvim-cursor/history/ with timestamp in filename
-- - Sending the current file contents to cursor-agent
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

-- Parse timestamp from filename like: 2025-02-04_14-30-45.md
-- @return number|nil unix timestamp (seconds) if parseable
local function parse_timestamp_from_filename(filename)
  local y, mo, d, h, mi, s = filename:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)%-(%d%d)%.md$")
  if not y then
    return nil
  end
  return os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s),
  })
end

-- Return sorted history entries (new -> old).
-- Sorting strategy:
-- 1) Prefer timestamp parsed from filename (YYYY-MM-DD_HH-MM-SS.md)
-- 2) Fallback to filesystem mtime (seconds)
-- 3) Tie-break by filename (descending)
local function list_history_files_sorted(config)
  config = config or {}
  local dir = history_dir_path(config)

  if vim.fn.isdirectory(dir) ~= 1 then
    return {}, dir
  end

  local files = vim.fn.readdir(dir)
  local entries = {}

  for _, f in ipairs(files) do
    if f:match("%.md$") then
      local fullpath = dir .. "/" .. f
      local ts = parse_timestamp_from_filename(f)

      if not ts then
        -- getftime() returns seconds since epoch, or -1 on error
        local ft = vim.fn.getftime(fullpath)
        if type(ft) == "number" and ft >= 0 then
          ts = ft
        else
          ts = 0
        end
      end

      table.insert(entries, {
        name = f,
        path = fullpath,
        ts = ts,
      })
    end
  end

  table.sort(entries, function(a, b)
    if a.ts ~= b.ts then
      return a.ts > b.ts
    end
    return a.name > b.name
  end)

  return entries, dir
end

local function is_plugin_prompt_file_buffer(buf, config)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  if vim.bo[buf].buftype ~= "" then
    return false
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if not path or path == "" then
    return false
  end

  local abs_path = vim.fn.fnamemodify(path, ":p")
  local history_dir = vim.fn.fnamemodify(history_dir_path(config), ":p"):gsub("/$", "")
  local history_prefix = history_dir .. "/"

  if abs_path:sub(1, #history_prefix) ~= history_prefix then
    return false
  end

  local filename = vim.fn.fnamemodify(abs_path, ":t")
  return parse_timestamp_from_filename(filename) ~= nil
end

local function has_file_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.fn.buflisted(buf) == 1 then
      if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
        return true
      end
    end
  end
  return false
end

local function find_replacement_file_buffer(excluded_buf)
  for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
    if candidate ~= excluded_buf
      and vim.api.nvim_buf_is_valid(candidate)
      and vim.fn.buflisted(candidate) == 1
      and vim.bo[candidate].buftype == ""
      and vim.api.nvim_buf_get_name(candidate) ~= "" then
      return candidate
    end
  end
  return nil
end

local function replace_prompt_in_open_windows(buf)
  local replacement = find_replacement_file_buffer(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      if replacement then
        vim.api.nvim_win_set_buf(win, replacement)
      else
        vim.api.nvim_win_call(win, function()
          vim.cmd("enew")
        end)
      end
    end
  end
end

local function close_sent_prompt_buffer_if_needed(buf, config)
  if not is_plugin_prompt_file_buffer(buf, config) then
    return
  end

  -- To preserve split layout, first replace this prompt buffer in every window
  -- that currently shows it, then delete the prompt buffer itself.
  replace_prompt_in_open_windows(buf)

  local ok, err = pcall(vim.api.nvim_buf_delete, buf, {})
  if not ok then
    vim.notify("Failed to close sent prompt buffer: " .. tostring(err), vim.log.levels.WARN)
    return
  end

  if not has_file_buffers() then
    vim.cmd("enew")
  end
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

local function current_buffer_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  if text == "" then
    return "\n"
  end
  return text .. "\n"
end

-- Send current buffer's file contents to cursor-agent.
-- Ensures at least one terminal exists and shows it, then sends the text.
-- Saves the current buffer if modified so the file exists on disk for the agent.
-- @param config Plugin config (for terminal/tabs)
function M.send_prompt_file_to_agent(config)
  local buf = vim.api.nvim_get_current_buf()
  local source_buf = buf
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

  local text_to_send = current_buffer_text(buf)
  vim.defer_fn(function()
    local active_id = tabs.get_active()
    if active_id and terminal.is_running(active_id) then
      local sent = terminal.send_text(text_to_send, active_id)
      if sent then
        vim.notify("Sent current file contents to agent", vim.log.levels.INFO)
        close_sent_prompt_buffer_if_needed(source_buf, config)
      end
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
  local ok = pcall(require, "telescope")
  if not ok then
    vim.notify("telescope.nvim is required for CursorAgentHistoryTelescope", vim.log.levels.WARN)
    return
  end

  local entries, dir = list_history_files_sorted(config)
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.fn.mkdir(dir, "p")
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local make_entry = require("telescope.make_entry")
  local previewers = require("telescope.previewers")
  local sorters = require("telescope.sorters")

  local results = {}
  for _, e in ipairs(entries) do
    -- Feed relative names to the file entry maker with cwd=dir
    table.insert(results, e.name)
  end

  local entry_maker = make_entry.gen_from_file({
    cwd = dir,
  })

  -- Ensure stable chronological order when prompt is empty, but keep
  -- normal Telescope file filtering/sorting when the user types.
  local base_sorter = conf.file_sorter({})
  local chronological_sorter = sorters.Sorter:new({
    discard = base_sorter.discard,
    scoring_function = function(_, prompt, line, entry, cb_add, cb_filter)
      if not prompt or prompt == "" then
        return 1
      end
      return base_sorter:scoring_function(prompt, line, entry, cb_add, cb_filter)
    end,
    highlighter = function(_, prompt, display)
      if base_sorter.highlighter and prompt and prompt ~= "" then
        return base_sorter:highlighter(prompt, display)
      end
      return {}
    end,
  })

  -- Use a custom file previewer so we can enable wrapping in the preview window.
  -- Telescope's default file previewer typically uses 'nowrap', which is painful for
  -- long prompt lines.
  local history_previewer = previewers.new_buffer_previewer({
    title = "Prompt preview",
    define_preview = function(self, entry, _status)
      local path = entry.path or entry.value
      if not path or path == "" then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No file to preview" })
        return
      end

      -- Reuse Telescope's built-in file loading logic (respects previewer config).
      previewers.buffer_previewer_maker(path, self.state.bufnr, { winid = self.state.winid })

      -- Enable wrapping in the preview window.
      local winid = self.state.winid
      if winid and vim.api.nvim_win_is_valid(winid) then
        if vim.api.nvim_set_option_value then
          pcall(vim.api.nvim_set_option_value, "wrap", true, { win = winid })
          pcall(vim.api.nvim_set_option_value, "linebreak", true, { win = winid })
          pcall(vim.api.nvim_set_option_value, "breakindent", true, { win = winid })
        else
          pcall(function() vim.wo[winid].wrap = true end)
          pcall(function() vim.wo[winid].linebreak = true end)
          pcall(function() vim.wo[winid].breakindent = true end)
        end
      end
    end,
  })

  pickers.new({}, {
    prompt_title = "Prompt history",
    finder = finders.new_table({
      results = results,
      entry_maker = entry_maker,
    }),
    sorter = chronological_sorter,
    tiebreak = function()
      return false
    end,
    previewer = history_previewer,
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local path = selection.path or selection.value
          if path and path ~= "" then
            vim.cmd("edit " .. vim.fn.fnameescape(path))
          end
        end
      end)
      return true
    end,
  }):find()
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
  local source_buf = buf
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

  local text_to_send = current_buffer_text(buf)
  vim.defer_fn(function()
    local active_id = tabs.get_active()
    if active_id and terminal.is_running(active_id) then
      local sent = terminal.send_text(text_to_send, active_id)
      if sent then
        vim.notify("Sent current file contents to new agent", vim.log.levels.INFO)
        close_sent_prompt_buffer_if_needed(source_buf, config)
      end
    end
  end, 100)
end

return M
