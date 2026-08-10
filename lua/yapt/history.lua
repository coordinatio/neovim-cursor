-- Prompt history workflow for yapt.nvim plugin
--
-- Provides:
-- - Creating a new markdown file in ${CWD}/.nvim-yapt/history/ with timestamp in filename
-- - Sending the current file contents to the active terminal
--
local terminal = require("yapt.terminal")
local tabs = require("yapt.tabs")
local picker = require("yapt.picker")
local util = require("yapt.util")

local M = {}

-- Create history directory path (relative to CWD)
local function history_dir_path(cfg)
  local cwd = vim.fn.getcwd()
  local dir = (cfg and cfg.history and cfg.history.dir) or ".nvim-yapt/history"
  if dir:match("^/") then
    return dir
  end
  return cwd .. "/" .. dir:gsub("/$", "")
end

-- Parse timestamp from filename like: 2025-02-04_14-30-45.md
-- Also accepts a collision suffix (2025-02-04_14-30-45_1.md) so that
-- auto-created files from same-second sends are still recognized as
-- prompt-file buffers (and thus closed after send).
-- @return number|nil unix timestamp (seconds) if parseable
local function parse_timestamp_from_filename(filename)
  local y, mo, d, h, mi, s = filename:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)%-(%d%d)(_?%d*)%.md$")
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

-- Persist a prompt-file buffer to disk when the user leaves it, so it shows
-- up in the history Telescope picker (:PTHistory) and :PTLast without a
-- manual :write. No-op unless the buffer is a plugin prompt file and has
-- unsaved changes; an empty just-created prompt you abandon is left alone.
local function autosave_prompt_buffer(buf, config)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not is_plugin_prompt_file_buffer(buf, config) then
    return
  end
  if not vim.bo[buf].modified then
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if not path or path == "" then
    return
  end

  local dir = history_dir_path(config)
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.fn.mkdir(dir, "p")
  end

  -- Use :write (not writefile) so Neovim updates the buffer's file timestamp
  -- and does not prompt to reload when returning to the buffer.
  local ok = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! noautocmd write")
    end)
  end)
  if not ok then
    util.notify("Failed to autosave prompt file: " .. path, vim.log.levels.WARN)
  end
end

-- Register autocmds that persist prompt-file buffers to disk when the user
-- leaves them (or quits Neovim), so they appear in the history Telescope
-- picker without a manual :write. Idempotent: recreates the augroup on each
-- call.
function M.setup_autosave_autocmds(config)
  local group = vim.api.nvim_create_augroup("yapt_history_autosave", { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "BufHidden" }, {
    group = group,
    callback = function(args)
      autosave_prompt_buffer(args.buf, config)
    end,
  })
  -- Quitting Neovim fires no per-buffer leave event for the current buffer,
  -- so sweep every loaded prompt buffer on exit to avoid losing changes.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          autosave_prompt_buffer(buf, config)
        end
      end
    end,
  })
end

local function replace_prompt_in_open_windows(buf, replacement)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_set_buf(win, replacement)
    end
  end
end

local function close_sent_prompt_buffer_if_needed(buf, config)
  if not is_plugin_prompt_file_buffer(buf, config) then
    return
  end

  local skip_prompt = function(b)
    return is_plugin_prompt_file_buffer(b, config)
  end

  local replacement = util.find_previous_buffer(buf, skip_prompt)
    or util.find_file_buffer(buf, skip_prompt)
    or util.find_empty_unnamed_buffer(buf)

  if not replacement then
    return
  end

  replace_prompt_in_open_windows(buf, replacement)

  local ok, err = pcall(vim.api.nvim_buf_delete, buf, {})
  if not ok then
    util.notify("Failed to close sent prompt buffer: " .. tostring(err), vim.log.levels.WARN)
    return
  end
end

local function prepare_prompt_buffer_for_fullscreen(buf, config)
  if not is_plugin_prompt_file_buffer(buf, config) then
    return
  end

  local skip_prompt = function(b)
    return is_plugin_prompt_file_buffer(b, config)
  end

  local replacement = util.find_or_create_restore_buffer(buf, skip_prompt)
  replace_prompt_in_open_windows(buf, replacement)
end

-- Expose history dir path for other modules
function M.history_dir_path(config)
  return history_dir_path(config)
end

-- Build a unique timestamped history file path (.md), guarding against
-- same-second collisions by appending _1, _2, ... before the extension.
-- Collision-suffixed names still parse via parse_timestamp_from_filename.
local function unique_history_path(dir)
  local base = os.date("%Y-%m-%d_%H-%M-%S")
  local fullpath = dir .. "/" .. base .. ".md"
  local counter = 1
  while vim.fn.filereadable(fullpath) == 1 do
    fullpath = dir .. "/" .. base .. "_" .. counter .. ".md"
    counter = counter + 1
  end
  return fullpath
end

-- Persist an unnamed/new buffer to a fresh prompt-history file, converting
-- the buffer in place so it becomes a recognized plugin prompt-file buffer.
-- Reuses the same naming scheme (timestamped .md) as create_prompt_file.
-- @param lines string[] buffer lines to write (computed once by the caller)
-- @return string|nil full path of the created file, or nil on failure
local function persist_unnamed_buffer_to_history(buf, lines, config)
  local dir = history_dir_path(config)
  vim.fn.mkdir(dir, "p")
  if vim.fn.isdirectory(dir) ~= 1 then
    util.notify("Failed to create history directory: " .. dir, vim.log.levels.ERROR)
    return nil
  end

  local fullpath = unique_history_path(dir)

  local wrote = pcall(vim.fn.writefile, lines, fullpath)
  if not wrote or vim.fn.filereadable(fullpath) ~= 1 then
    util.notify("Failed to write history file: " .. fullpath, vim.log.levels.ERROR)
    return nil
  end

  -- Convert the buffer in place: it now IS the history prompt file, so it
  -- satisfies is_plugin_prompt_file_buffer and inherits close-after-send.
  local renamed, err = pcall(vim.api.nvim_buf_set_name, buf, fullpath)
  if not renamed then
    util.notify("Failed to associate buffer with history file: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end
  vim.bo[buf].modified = false

  return fullpath
end

-- Create a new prompt file in history dir and open it in the current window
-- @param config Plugin config (must have history.dir)
function M.create_prompt_file(config)
  config = config or {}
  local dir = history_dir_path(config)
  vim.fn.mkdir(dir, "p")
  local fullpath = unique_history_path(dir)
  vim.cmd("edit " .. vim.fn.fnameescape(fullpath))
  util.notify("Created " .. fullpath, vim.log.levels.INFO)
end

local function current_buffer_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  if text == "" then
    return "\n"
  end
  return text .. "\n"
end

-- Send buffered text to whichever terminal is currently active and report success.
local function send_to_active_terminal(text, source_buf, config, success_message, target_id)
  local active_id = target_id or tabs.get_active()
  if not active_id or not terminal.is_running(active_id) then
    return
  end
  local sent = terminal.send_text(text, active_id)
  if sent then
    util.notify(success_message or "Sent current file contents to terminal", vim.log.levels.INFO)
    close_sent_prompt_buffer_if_needed(source_buf, config)
  end
end

-- Create a fresh terminal (via picker) and send `text` to it once it boots.
-- @param display_mode string|nil "split" (default) or "fullscreen"
-- @param name string|nil optional terminal name
local function pick_create_and_send(config, text, source_buf, success_message, display_mode, name)
  picker.pick_command(config, function(cmd)
    if not cmd then return end
    if display_mode == "fullscreen" then
      prepare_prompt_buffer_for_fullscreen(source_buf, config)
    end

    tabs.create_terminal(name, config, cmd, display_mode)
    vim.defer_fn(function()
      send_to_active_terminal(text, source_buf, config, success_message)
    end, 200)
  end)
end

-- Read current buffer text for send, with optional soft mode.
-- Soft mode: no warnings; returns nil when empty or non-file (used by create-maybe-send).
-- Strict mode: warns and aborts on non-file or empty buffers (used by :PTSend).
-- Unnamed buffers with content are persisted to prompt history first.
-- @param config Plugin config
-- @param opts table|nil { soft = boolean }
-- @return buf, text|nil  or nil, nil when there is nothing sendable
local function current_file_text(config, opts)
  opts = opts or {}
  local soft = opts.soft == true
  local buf = vim.api.nvim_get_current_buf()

  if vim.bo[buf].buftype ~= "" then
    if not soft then
      util.notify("Current buffer is not a normal file buffer", vim.log.levels.WARN)
    end
    return nil, nil
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.trim(table.concat(lines, "\n")) == "" then
    if not soft then
      util.notify("Current buffer is empty — nothing to send", vim.log.levels.WARN)
    end
    return nil, nil
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if path == nil or path == "" then
    local new_path = persist_unnamed_buffer_to_history(buf, lines, config)
    if not new_path then
      return nil, nil
    end
    util.notify("Saved new buffer as " .. new_path, vim.log.levels.INFO)
    return buf, table.concat(lines, "\n") .. "\n"
  end

  if vim.bo[buf].modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("write")
    end)
  end
  return buf, current_buffer_text(buf)
end

-- Send current buffer's file contents to the active terminal.
-- Ensures at least one terminal exists and shows it (in its preferred
-- display mode, so a fullscreen terminal stays fullscreen), then sends the text.
-- Saves the current buffer if modified so the file exists on disk for the CLI.
-- @param config Plugin config (for terminal/tabs)
function M.send_prompt_file_to_terminal(config)
  local source_buf, text_to_send = current_file_text(config)
  if not source_buf then
    return
  end

  if not tabs.has_terminals() then
    pick_create_and_send(config, text_to_send, source_buf)
    return
  end

  local last_id = tabs.get_last()
  if not last_id then
    pick_create_and_send(config, text_to_send, source_buf)
    return
  end

  local term_meta = tabs.get_terminal(last_id)
  local stored_cmd = term_meta and term_meta.command

  -- Tab-local visibility: show/rehome when not in this tabpage; force-insert for send.
  if not terminal.is_visible(last_id) then
    terminal.show_in_preferred_mode(config, last_id, stored_cmd)
  else
    terminal.apply_ui_state(last_id, { force_insert = true })
  end

  vim.defer_fn(function()
    send_to_active_terminal(text_to_send, source_buf, config, nil, last_id)
  end, 100)
end

-- Send current buffer's file contents to the active terminal, forcing fullscreen display.
-- Like send_prompt_file_to_terminal, but always shows the terminal in fullscreen
-- (promoting from split if needed) before sending.
-- Saves the current buffer if modified so the file exists on disk for the CLI.
-- @param config Plugin config (for terminal/tabs)
function M.send_prompt_file_to_terminal_fullscreen(config)
  local source_buf, text_to_send = current_file_text(config)
  if not source_buf then
    return
  end

  if not tabs.has_terminals() then
    pick_create_and_send(config, text_to_send, source_buf, nil, "fullscreen")
    return
  end

  local last_id = tabs.get_last()
  if not last_id then
    pick_create_and_send(config, text_to_send, source_buf, nil, "fullscreen")
    return
  end

  local term_meta = tabs.get_terminal(last_id)
  local stored_cmd = term_meta and term_meta.command

  if terminal.is_fullscreen_active(last_id) then
    if terminal.is_visible(last_id) then
      terminal.apply_ui_state(last_id, { force_insert = true })
    else
      -- Fullscreen only in another tabpage: rehome here (do not jump tabs).
      terminal.show_in_preferred_mode(config, last_id, stored_cmd)
    end
  else
    prepare_prompt_buffer_for_fullscreen(source_buf, config)

    terminal.toggle_fullscreen(config, last_id, stored_cmd, { force_insert = true })
  end

  vim.defer_fn(function()
    send_to_active_terminal(text_to_send, source_buf, config, nil, last_id)
  end, 100)
end

-- Always create a new terminal session. If the current buffer has sendable
-- content, send it after the terminal boots; otherwise only create.
-- @param config Plugin config
-- @param opts table|nil { display_mode = "split"|"fullscreen", name = string|nil }
function M.create_terminal_maybe_send(config, opts)
  opts = opts or {}
  local display_mode = opts.display_mode or "split"
  local name = opts.name

  local source_buf, text_to_send = current_file_text(config, { soft = true })
  if source_buf and text_to_send then
    pick_create_and_send(
      config,
      text_to_send,
      source_buf,
      "Sent current file contents to new terminal",
      display_mode,
      name
    )
    return
  end

  picker.pick_command(config, function(cmd)
    if not cmd then return end
    tabs.create_terminal(name, config, cmd, display_mode)
  end)
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
    util.notify("telescope.nvim is required for PTHistory", vim.log.levels.WARN)
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
    table.insert(results, e.name)
  end

  local entry_maker = make_entry.gen_from_file({
    cwd = dir,
  })

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

  local history_previewer = previewers.new_buffer_previewer({
    title = "Prompt preview",
    define_preview = function(self, entry, _status)
      local path = entry.path or entry.value
      if not path or path == "" then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No file to preview" })
        return
      end

      previewers.buffer_previewer_maker(path, self.state.bufnr, { winid = self.state.winid })

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
    util.notify("No prompt files in history", vim.log.levels.WARN)
    return
  end
  local buf = vim.fn.bufadd(path)
  if vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_set_current_buf(buf)
  else
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end
end

return M
