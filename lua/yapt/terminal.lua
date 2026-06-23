-- Terminal management for yapt.nvim plugin
--
-- This module handles the low-level terminal operations:
-- - Creating terminal buffers and windows
-- - Managing terminal visibility (show/hide) for both split and fullscreen modes
-- - Sending text to terminal buffers
-- - Terminal lifecycle (on_exit callbacks)
-- - Terminal mode keybindings (configured by user)
--
-- Architecture:
-- - Stores terminal instances with buffers, windows, job IDs, and last
--   used display_mode ("split" | "fullscreen")
-- - Supports multiple terminals with unique IDs
-- - Tracks at most one fullscreen terminal at a time (singleton state)
-- - Cleanup callbacks notify tabs.lua when terminals exit
--
local config_module = require("yapt.config")
local util = require("yapt.util")

local M = {}

-- State tracking for multiple terminals
local terminals = {}  -- Table of terminal instances keyed by ID
local active_id = nil  -- Currently active terminal ID
local default_id = "default"  -- Default terminal ID for backward compatibility
local cleanup_callbacks = {}  -- Callbacks called when a terminal exits (used by tabs.lua)

local forward_seqs = {}
local forward_seq_counter = 0

local special_key_defs = {
  {"<Up>",       "\x1b[A"},
  {"<Down>",     "\x1b[B"},
  {"<Right>",    "\x1b[C"},
  {"<Left>",     "\x1b[D"},
  {"<PageUp>",   "\x1b[5~"},
  {"<PageDown>", "\x1b[6~"},
  {"<Home>",     "\x1b[H"},
  {"<End>",      "\x1b[F"},
  {"<Insert>",   "\x1b[2~"},
  {"<Delete>",   "\x1b[3~"},
  {"<F1>",       "\x1bOP"},
  {"<F2>",       "\x1bOQ"},
  {"<F3>",       "\x1bOR"},
  {"<F4>",       "\x1bOS"},
  {"<F5>",       "\x1b[15~"},
  {"<F6>",       "\x1b[17~"},
  {"<F7>",       "\x1b[18~"},
  {"<F8>",       "\x1b[19~"},
  {"<F9>",       "\x1b[20~"},
  {"<F10>",      "\x1b[21~"},
  {"<F11>",      "\x1b[23~"},
  {"<F12>",      "\x1b[24~"},
  {"<Tab>",      "\x09"},
  {"<BS>",       "\x7f"},
  {"<CR>",       "\x0d"},
  {"<S-Up>",     "\x1b[1;2A"},
  {"<S-Down>",   "\x1b[1;2B"},
  {"<S-Right>",  "\x1b[1;2C"},
  {"<S-Left>",   "\x1b[1;2D"},
  {"<S-PageUp>",   "\x1b[5;2~"},
  {"<S-PageDown>", "\x1b[6;2~"},
  {"<S-Home>",     "\x1b[1;2H"},
  {"<S-End>",      "\x1b[1;2F"},
  {"<C-Up>",     "\x1b[1;5A"},
  {"<C-Down>",   "\x1b[1;5B"},
  {"<C-Right>",  "\x1b[1;5C"},
  {"<C-Left>",   "\x1b[1;5D"},
  {"<S-Tab>",    "\x1b[Z"},
  {"<Space>",    " "},
  {"<C-M-u>",    "\x1b\x15"},
  {"<C-M-d>",    "\x1b\x04"},
}

local special_key_map = nil

local function get_special_key_map()
  if special_key_map then return special_key_map end
  special_key_map = {}
  for _, pair in ipairs(special_key_defs) do
    local nvim_key = vim.api.nvim_replace_termcodes(pair[1], true, false, true)
    special_key_map[nvim_key] = pair[2]
  end
  return special_key_map
end

local function get_job_id_for_current_buf()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then return nil end
  local job_id = vim.b[buf].terminal_job_id
  if job_id then return job_id end
  for _, term in pairs(terminals) do
    if term.buf == buf and term.job_id then
      return term.job_id
    end
  end
  return nil
end

local function neovim_key_to_termseq(key)
  if #key == 1 then
    local b = string.byte(key)
    if b == 27 then return nil end
    return key
  end
  local kmap = get_special_key_map()
  if kmap[key] then return kmap[key] end
  return key
end

local function do_send_key(key)
  local seq = neovim_key_to_termseq(key)
  if not seq then return false end
  local job_id = get_job_id_for_current_buf()
  if not job_id then return false end
  vim.api.nvim_chan_send(job_id, seq)
  return true
end

-- Fullscreen mode singleton state.
-- At most one terminal can be displayed fullscreen at a time because
-- "fullscreen" simply means "took over a window that was showing something
-- else". The saved_win/saved_buf pair lets us hand the window back.
local fullscreen_state = {
  active = false,       -- True while a terminal is mounted in saved_win
  terminal_id = nil,    -- ID of the terminal mounted fullscreen
  saved_win = nil,      -- Window we took over
  saved_buf = nil,      -- Buffer that was in saved_win before we took over
}

local function reset_fullscreen_state()
  fullscreen_state.active = false
  fullscreen_state.terminal_id = nil
  fullscreen_state.saved_win = nil
  fullscreen_state.saved_buf = nil
end

local function get_terminal(id)
  id = id or active_id or default_id
  return terminals[id]
end

local function is_visible(id)
  local term = get_terminal(id)
  if not term then return false end
  return term.win ~= nil and vim.api.nvim_win_is_valid(term.win)
end

local function is_buffer_valid(id)
  local term = get_terminal(id)
  if not term then return false end
  return term.buf ~= nil and vim.api.nvim_buf_is_valid(term.buf)
end

function M.is_running(id)
  if not is_buffer_valid(id) then
    return false
  end

  local term = get_terminal(id)
  if term and term.job_id then
    local job_info = vim.fn.jobwait({term.job_id}, 0)
    return job_info[1] == -1  -- -1 means still running
  end

  return false
end

function M.send_passthrough_key()
  if not get_job_id_for_current_buf() then
    vim.notify("Not in a terminal buffer", vim.log.levels.WARN)
    return
  end
  local ok, key = pcall(vim.fn.getcharstr)
  if not ok or key == "" then return end
  do_send_key(key)
end

function M.send_forward_key(id)
  local seq = forward_seqs[id]
  if not seq then return end
  local job_id = get_job_id_for_current_buf()
  if not job_id then return end
  vim.api.nvim_chan_send(job_id, seq)
end

-- Verify the fullscreen window still actually shows the tracked terminal.
-- The user can move things out from under us (e.g. `:b otherfile`); when
-- that happens we treat fullscreen as no longer active.
local function fullscreen_window_still_valid()
  if not fullscreen_state.active then return false end
  if not fullscreen_state.saved_win
    or not vim.api.nvim_win_is_valid(fullscreen_state.saved_win) then
    return false
  end
  local term = get_terminal(fullscreen_state.terminal_id)
  if not term or not term.buf or not vim.api.nvim_buf_is_valid(term.buf) then
    return false
  end
  return vim.api.nvim_win_get_buf(fullscreen_state.saved_win) == term.buf
end

-- Reconcile fullscreen_state with reality. Call before reading or acting on it.
local function sync_fullscreen_state()
  if fullscreen_state.active and not fullscreen_window_still_valid() then
    local stale_term = get_terminal(fullscreen_state.terminal_id)
    if stale_term then stale_term.win = nil end
    reset_fullscreen_state()
  end
end

local function hide(id)
  id = id or active_id or default_id
  if is_visible(id) then
    local term = get_terminal(id)
    if term then
      vim.api.nvim_win_hide(term.win)
      term.win = nil
    end
  end
end

function M.hide(id)
  hide(id)
end

local function show_fullscreen(id)
  local term = get_terminal(id)
  if not term or not term.buf then return false end

  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)

  if vim.bo[current_buf].buftype ~= "terminal" then
    fullscreen_state.saved_buf = current_buf
  else
    fullscreen_state.saved_buf = util.find_or_create_restore_buffer(current_buf)
  end

  fullscreen_state.saved_win = current_win
  fullscreen_state.terminal_id = id
  fullscreen_state.active = true

  vim.api.nvim_win_set_buf(current_win, term.buf)
  term.win = current_win
  term.display_mode = "fullscreen"
  active_id = id
  return true
end

local function hide_fullscreen()
  sync_fullscreen_state()
  if not fullscreen_state.active then return end

  if fullscreen_state.saved_win and vim.api.nvim_win_is_valid(fullscreen_state.saved_win) then
    local win = fullscreen_state.saved_win
    local replacement = fullscreen_state.saved_buf
    if not replacement or not vim.api.nvim_buf_is_valid(replacement) then
      replacement = util.find_or_create_restore_buffer()
    end
    vim.api.nvim_win_set_buf(win, replacement)
  end

  local term = get_terminal(fullscreen_state.terminal_id)
  if term then term.win = nil end

  reset_fullscreen_state()
end

function M.is_fullscreen_active(id)
  sync_fullscreen_state()
  if id then
    return fullscreen_state.active and fullscreen_state.terminal_id == id
  end
  return fullscreen_state.active
end

function M.hide_fullscreen()
  hide_fullscreen()
end

local function show(id, config)
  id = id or active_id or default_id
  if not is_buffer_valid(id) then
    return false
  end

  local term = get_terminal(id)
  if not term then
    return false
  end

  local size
  if config.split.position == "right" or config.split.position == "left" then
    size = math.floor(vim.o.columns * config.split.size)
  else
    size = math.floor(vim.o.lines * config.split.size)
  end

  local split_cmd
  if config.split.position == "right" then
    split_cmd = "rightbelow vsplit"
  elseif config.split.position == "left" then
    split_cmd = "leftabove vsplit"
  elseif config.split.position == "top" then
    split_cmd = "leftabove split"
  else  -- bottom
    split_cmd = "rightbelow split"
  end

  vim.cmd(split_cmd)
  term.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(term.win, term.buf)

  if config.split.position == "right" or config.split.position == "left" then
    vim.api.nvim_win_set_width(term.win, size)
  else
    vim.api.nvim_win_set_height(term.win, size)
  end

  term.display_mode = "split"
  active_id = id

  return true
end

-- Create a new terminal instance (reusable function for creating terminals).
-- @param id string Terminal ID
-- @param config table Plugin config
-- @param command string|nil Command to run (resolved via config_module if nil)
-- @param display_mode string|nil "split" (default) or "fullscreen"
local function create_terminal_instance(id, config, command, display_mode)
  display_mode = display_mode or "split"
  command = config_module.resolve_command(command, config)

  if not terminals[id] then
    terminals[id] = {
      buf = nil,
      win = nil,
      job_id = nil,
      id = id,
      display_mode = display_mode,
    }
  end

  local term = terminals[id]
  term.display_mode = display_mode
  term.buf = vim.api.nvim_create_buf(false, true)

  if display_mode == "fullscreen" then
    show_fullscreen(id)
  else
    show(id, config)
  end

  term.job_id = vim.fn.termopen(command, {
    on_exit = function(_, exit_code, _)
      -- Capture fullscreen state before clearing it; we may need to restore
      -- the user's window after the buffer is gone.
      local was_fullscreen = fullscreen_state.active and fullscreen_state.terminal_id == id
      local fs_saved_win = fullscreen_state.saved_win
      local fs_saved_buf = fullscreen_state.saved_buf

      if was_fullscreen then
        reset_fullscreen_state()
      end

      term.job_id = nil
      if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
        vim.api.nvim_buf_delete(term.buf, { force = true })
      end
      term.buf = nil
      term.win = nil

      if term.forward_ids then
        for _, fwd_id in ipairs(term.forward_ids) do
          forward_seqs[fwd_id] = nil
        end
        term.forward_ids = nil
      end

      terminals[id] = nil

      if active_id == id then
        active_id = nil
      end

      for _, callback in ipairs(cleanup_callbacks) do
        pcall(callback, id, exit_code)
      end

      if config.term_opts.on_close then
        config.term_opts.on_close(exit_code)
      end

      if was_fullscreen then
        vim.schedule(function()
          if fs_saved_win and vim.api.nvim_win_is_valid(fs_saved_win) then
            local replacement = fs_saved_buf
            if not replacement or not vim.api.nvim_buf_is_valid(replacement) then
              replacement = util.find_or_create_restore_buffer()
            end
            vim.api.nvim_win_set_buf(fs_saved_win, replacement)
          end
        end)
      end
    end,
  })

  local term_keys = vim.tbl_deep_extend("force", {}, config_module.defaults.terminal_keybindings, config.terminal_keybindings or {})
  if config.terminal_keybindings and config.terminal_keybindings.forward_keys then
    term_keys.forward_keys = config.terminal_keybindings.forward_keys
  end

  -- Backward compatibility: if someone only set `exit`, treat it as `hide`.
  if (term_keys.hide == nil or term_keys.hide == "") and term_keys.exit and term_keys.exit ~= "" then
    term_keys.hide = term_keys.exit
  end
  -- Always use one key for both actions.
  term_keys.exit = term_keys.hide

  if term_keys.exit and term_keys.exit ~= "" then
    vim.api.nvim_buf_set_keymap(term.buf, 't', term_keys.exit, '<C-\\><C-n>:lua require("yapt").hide_from_terminal_handler()<CR>', {
      noremap = true,
      silent = true,
      desc = "Hide terminal window"
    })
  end

  if term_keys.hide and term_keys.hide ~= "" then
    vim.api.nvim_buf_set_keymap(term.buf, 'n', term_keys.hide, ':lua require("yapt").hide_from_terminal_handler()<CR>', {
      noremap = true,
      silent = true,
      desc = "Hide terminal window"
    })
  end

  if term_keys.new and term_keys.new ~= "" then
    vim.api.nvim_buf_set_keymap(term.buf, 't', term_keys.new, '<C-\\><C-n>:lua require("yapt").new_terminal_from_terminal_handler()<CR>', {
      noremap = true,
      silent = true,
      desc = "Create new terminal (hide current first)"
    })
  end

  if term_keys.rename and term_keys.rename ~= "" then
    vim.api.nvim_buf_set_keymap(term.buf, 't', term_keys.rename, '<C-\\><C-n>:lua require("yapt").rename_terminal_handler()<CR>', {
      noremap = true,
      silent = true,
      desc = "Rename current terminal"
    })
  end

  if term_keys.select and term_keys.select ~= "" then
    vim.api.nvim_buf_set_keymap(term.buf, 't', term_keys.select, '<C-\\><C-n>:lua require("yapt").select_terminal_from_terminal_handler()<CR>', {
      noremap = true,
      silent = true,
      desc = "Select terminal"
    })
  end

  if term_keys.prompt_last and term_keys.prompt_last ~= "" then
    vim.api.nvim_buf_set_keymap(term.buf, 't', term_keys.prompt_last, '<C-\\><C-n>:lua require("yapt").open_last_prompt_from_terminal_handler()<CR>', {
      noremap = true,
      silent = true,
      desc = "Open last prompt file"
    })
  end

  if term_keys.toggle_fullscreen and term_keys.toggle_fullscreen ~= "" then
    vim.api.nvim_buf_set_keymap(term.buf, 't', term_keys.toggle_fullscreen, '<C-\\><C-n>:lua require("yapt").fullscreen_toggle_from_terminal_handler()<CR>', {
      noremap = true,
      silent = true,
      desc = "Toggle fullscreen mode"
    })
    vim.api.nvim_buf_set_keymap(term.buf, 'n', term_keys.toggle_fullscreen, ':lua require("yapt").fullscreen_toggle_from_terminal_handler()<CR>', {
      noremap = true,
      silent = true,
      desc = "Toggle fullscreen mode"
    })
  end

  if term_keys.passthrough and term_keys.passthrough ~= "" then
    local passthrough_rhs = '<Cmd>lua require("yapt.terminal").send_passthrough_key()<CR>'
    vim.api.nvim_buf_set_keymap(term.buf, 'n', term_keys.passthrough, passthrough_rhs, {
      noremap = true,
      silent = true,
      desc = "Send next key to TUI application"
    })
  end

  if term_keys.forward_keys then
    term.forward_ids = {}
    for _, key in ipairs(term_keys.forward_keys) do
      forward_seq_counter = forward_seq_counter + 1
      local fwd_id = forward_seq_counter
      term.forward_ids[#term.forward_ids + 1] = fwd_id
      local nvim_key = vim.api.nvim_replace_termcodes(key, true, false, true)
      forward_seqs[fwd_id] = neovim_key_to_termseq(nvim_key)
      local rhs = string.format(
        '<Cmd>lua require("yapt.terminal").send_forward_key(%d)<CR>', fwd_id)
      vim.api.nvim_buf_set_keymap(term.buf, 'n', key, rhs, {
        noremap = true,
        silent = true,
        desc = "Forward " .. key .. " to TUI"
      })
      local neovide_key = key:gsub("^<C%-M%-(%l)>$", function(c)
        return "<M-C-" .. c:upper() .. ">"
      end)
      if neovide_key ~= key then
        vim.api.nvim_buf_set_keymap(term.buf, 'n', neovide_key, rhs, {
          noremap = true,
          silent = true,
          desc = "Forward " .. neovide_key .. " to TUI"
        })
      end
    end
  end

  vim.schedule(function() vim.cmd("startinsert") end)

  active_id = id

  if config.term_opts.on_open then
    config.term_opts.on_open()
  end

  return term
end

-- Toggle terminal visibility.
--
-- Semantics:
--   - If the terminal is visible (in any mode) -> hide it.
--   - Otherwise -> show it in split mode (creating it if needed).
--
-- Pressing the split-toggle key while the terminal is fullscreen no longer
-- silently demotes it to a split: it just hides, matching the expectation
-- that the toggle key toggles visibility.
function M.toggle(config, id, command)
  id = id or active_id or default_id
  sync_fullscreen_state()

  if fullscreen_state.active and fullscreen_state.terminal_id == id then
    hide_fullscreen()
    return
  end

  if is_visible(id) then
    hide(id)
  elseif is_buffer_valid(id) and M.is_running(id) then
    show(id, config)
    vim.schedule(function() vim.cmd("startinsert") end)
  else
    create_terminal_instance(id, config, command, "split")
  end
end

-- Toggle a terminal in fullscreen mode.
--
-- Semantics:
--   - If this terminal is already shown fullscreen -> hide it (giving the
--     window back to the user's previous buffer).
--   - If it is shown in a split -> hide the split, then take over the now
--     focused window.
--   - Otherwise -> show it (creating if needed) in fullscreen mode.
function M.toggle_fullscreen(config, id, command)
  id = id or active_id or default_id
  sync_fullscreen_state()

  if fullscreen_state.active and fullscreen_state.terminal_id == id then
    hide_fullscreen()
    return
  end

  -- A different terminal is currently fullscreen; release that first
  -- so we don't end up with two fullscreen entries fighting for state.
  if fullscreen_state.active then
    hide_fullscreen()
  end

  -- If this terminal is currently visible in a split, close that split.
  -- After nvim_win_hide focus shifts to a remaining window, which is the
  -- one we want to take over for fullscreen -- no need for vim.schedule.
  if is_visible(id) then
    hide(id)
  end

  if is_buffer_valid(id) and M.is_running(id) then
    show_fullscreen(id)
    vim.schedule(function() vim.cmd("startinsert") end)
  else
    create_terminal_instance(id, config, command, "fullscreen")
  end
end

-- Show the terminal in its preferred (last used) display mode.
-- Used by callers that want to *make the terminal visible* without toggling
-- (e.g. send_prompt_file_to_terminal), so the terminal doesn't get demoted from
-- fullscreen to split unexpectedly. No-op if already visible.
function M.show_in_preferred_mode(config, id, command)
  id = id or active_id or default_id
  sync_fullscreen_state()

  if fullscreen_state.active and fullscreen_state.terminal_id == id then
    return
  end
  if is_visible(id) then
    return
  end

  local term = get_terminal(id)
  local mode = (term and term.display_mode) or "split"

  if mode == "fullscreen" then
    if is_buffer_valid(id) and M.is_running(id) then
      show_fullscreen(id)
      vim.schedule(function() vim.cmd("startinsert") end)
    else
      create_terminal_instance(id, config, command, "fullscreen")
    end
  else
    if is_buffer_valid(id) and M.is_running(id) then
      show(id, config)
      vim.schedule(function() vim.cmd("startinsert") end)
    else
      create_terminal_instance(id, config, command, "split")
    end
  end
end

-- Send text to the terminal
function M.send_text(text, id)
  id = id or active_id or default_id

  if not M.is_running(id) then
    vim.notify("Terminal is not running", vim.log.levels.WARN)
    return false
  end

  local term = get_terminal(id)
  if term and term.job_id then
    if not text:match("\n$") then
      text = text .. "\n"
    end
    vim.api.nvim_chan_send(term.job_id, text)

    if term.win and vim.api.nvim_win_is_valid(term.win) then
      vim.api.nvim_set_current_win(term.win)
      vim.schedule(function() vim.cmd("startinsert") end)
    end

    return true
  end

  return false
end

-- Get terminal state (for debugging / coordination with other modules)
function M.get_state(id)
  id = id or active_id or default_id
  local term = get_terminal(id)

  if not term then
    return {
      id = id,
      exists = false,
      is_visible = false,
      is_running = false,
      display_mode = nil,
    }
  end

  return {
    id = id,
    buf = term.buf,
    win = term.win,
    job_id = term.job_id,
    display_mode = term.display_mode,
    is_visible = is_visible(id),
    is_running = M.is_running(id),
  }
end

-- Get the last preferred display mode for a terminal.
-- Returns "split" by default if the terminal is unknown.
function M.get_display_mode(id)
  local term = get_terminal(id)
  return (term and term.display_mode) or "split"
end

-- Register a cleanup callback (called when terminal exits)
-- @param callback function(id, exit_code)
function M.register_cleanup_callback(callback)
  table.insert(cleanup_callbacks, callback)
end

-- Expose internal functions for tabs module
M._create_terminal_instance = create_terminal_instance
M._get_terminal = get_terminal
M._set_active = function(id) active_id = id end
M._get_active_id = function() return active_id end

return M
