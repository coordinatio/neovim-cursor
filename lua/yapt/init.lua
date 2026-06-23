-- Main module for yapt.nvim plugin
--
-- This is the entry point for the plugin, providing:
-- - Plugin setup and configuration
-- - User-facing handlers for all operations (normal/visual/terminal mode)
-- - Keybinding and command registration
-- - Integration between config, terminal, tabs, history, and picker modules
--
-- Key handlers:
-- - normal_mode_handler():       Smart toggle in split mode
-- - fullscreen_toggle_handler(): Smart toggle in fullscreen mode
-- - visual_mode_handler():       Toggle (split) and send selection
-- - visual_fullscreen_mode_handler(): Toggle (fullscreen) and send selection
-- - new_terminal_handler():      Create new terminal in split
-- - new_fullscreen_handler():    Create new terminal in fullscreen
-- - select_terminal_handler():   Open fuzzy picker to select terminal
-- - rename_terminal_handler():   Rename active terminal
--
local config_module = require("yapt.config")
local terminal = require("yapt.terminal")
local tabs = require("yapt.tabs")
local picker = require("yapt.picker")
local history = require("yapt.history")

local M = {}
local config = {}

-- Plugin version (Semantic Versioning: MAJOR.MINOR.PATCH)
M.version = "2.0.0"

------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------

-- Toggle the last-active terminal in the requested display mode, creating
-- one through the picker if there is none yet.
-- Used by both normal-mode and fullscreen toggle keybindings.
local function smart_toggle(display_mode)
  local toggle_fn = (display_mode == "fullscreen")
    and terminal.toggle_fullscreen
    or terminal.toggle

  if not tabs.has_terminals() then
    picker.pick_command(config, function(cmd)
      tabs.create_terminal(nil, config, cmd, display_mode)
    end)
    return
  end

  local last_id = tabs.get_last()
  if not last_id then
    picker.pick_command(config, function(cmd)
      tabs.create_terminal(nil, config, cmd, display_mode)
    end)
    return
  end

  local term_meta = tabs.get_terminal(last_id)
  toggle_fn(config, last_id, term_meta and term_meta.command)
end

-- Build the @file:start-end link for the most recent visual selection.
local function visual_selection_link()
  local buf = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(buf)
  local start_line = vim.fn.getpos("'<")[2]
  local end_line = vim.fn.getpos("'>")[2]
  return "@" .. filepath .. ":" .. start_line .. "-" .. end_line
end

-- Send `text` to the currently active terminal after a delay.
-- The delay lets the picker / terminal startup settle before we feed input.
local function send_after(delay, text)
  vim.defer_fn(function()
    local active_id = tabs.get_active()
    if active_id and terminal.is_running(active_id) then
      terminal.send_text(text, active_id)
    end
  end, delay)
end

-- Toggle the terminal and send a visual-mode selection link in one go.
local function smart_toggle_with_selection(display_mode)
  local link = visual_selection_link()
  local toggle_fn = (display_mode == "fullscreen")
    and terminal.toggle_fullscreen
    or terminal.toggle

  if not tabs.has_terminals() then
    picker.pick_command(config, function(cmd)
      tabs.create_terminal(nil, config, cmd, display_mode)
      send_after(200, link)
    end)
    return
  end

  local last_id = tabs.get_last()
  if not last_id then
    picker.pick_command(config, function(cmd)
      tabs.create_terminal(nil, config, cmd, display_mode)
      send_after(200, link)
    end)
    return
  end

  local term_meta = tabs.get_terminal(last_id)
  toggle_fn(config, last_id, term_meta and term_meta.command)
  send_after(100, link)
end

-- Drop in front of any visual-mode keymap to leave visual mode and run a
-- handler against the just-finished selection (using `'<` and `'>`).
local function exit_visual_then(callback)
  return function()
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "x", false)
    vim.schedule(callback)
  end
end

------------------------------------------------------------
-- Public handlers
------------------------------------------------------------

function M.normal_mode_handler()
  smart_toggle("split")
end

function M.fullscreen_toggle_handler()
  smart_toggle("fullscreen")
end

function M.visual_mode_handler()
  smart_toggle_with_selection("split")
end

function M.visual_fullscreen_mode_handler()
  smart_toggle_with_selection("fullscreen")
end

function M.new_terminal_handler()
  picker.pick_command(config, function(cmd)
    tabs.create_terminal(nil, config, cmd, "split")
  end)
end

function M.new_fullscreen_handler()
  picker.pick_command(config, function(cmd)
    tabs.create_terminal(nil, config, cmd, "fullscreen")
  end)
end

-- Hide the terminal regardless of which mode it's currently displayed in.
-- Mounted on terminal-mode keymaps so a single key always "puts the terminal away".
function M.hide_from_terminal_handler()
  if terminal.is_fullscreen_active() then
    terminal.hide_fullscreen()
  else
    terminal.hide()
  end
end

-- From within a terminal: hide whatever mode it's in, then run the new-terminal flow.
-- Preserves the current display mode (fullscreen or split) for the new terminal.
function M.new_terminal_from_terminal_handler()
  local display_mode = terminal.is_fullscreen_active() and "fullscreen" or "split"

  if display_mode == "fullscreen" then
    terminal.hide_fullscreen()
  else
    terminal.hide()
  end

  vim.schedule(function()
    picker.pick_command(config, function(cmd)
      tabs.create_terminal(nil, config, cmd, display_mode)
    end)
  end)
end

-- From within a terminal: hide whatever mode it's in, then open the latest prompt buffer.
function M.open_last_prompt_from_terminal_handler()
  if terminal.is_fullscreen_active() then
    terminal.hide_fullscreen()
  else
    terminal.hide()
  end

  vim.schedule(function()
    history.open_last_prompt_buffer(config)
  end)
end

-- From within a terminal, swap between split and fullscreen presentation.
function M.fullscreen_toggle_from_terminal_handler()
  if terminal.is_fullscreen_active() then
    terminal.hide_fullscreen()
    return
  end

  local active_id = tabs.get_active()
  if not active_id then
    return
  end

  local term_meta = tabs.get_terminal(active_id)
  terminal.hide(active_id)
  vim.schedule(function()
    terminal.toggle_fullscreen(config, active_id, term_meta and term_meta.command)
  end)
end

function M.select_terminal_handler()
  picker.pick_terminal(config, function(selected_id)
    if selected_id then
      tabs.switch_to(selected_id, config)
    end
  end)
end

-- From within a terminal: capture the current display mode before the picker
-- opens, then switch to the selected terminal in the same mode.
function M.select_terminal_from_terminal_handler()
  local display_mode = terminal.is_fullscreen_active() and "fullscreen" or "split"

  picker.pick_terminal(config, function(selected_id)
    if selected_id then
      tabs.switch_to(selected_id, config, display_mode)
    end
  end)
end

function M.rename_terminal_handler()
  local active_id = tabs.get_active()

  if not active_id then
    vim.notify("No active terminal to rename. Create one with <leader>an", vim.log.levels.WARN)
    return
  end

  local term = tabs.get_terminal(active_id)
  local current_name = term and term.name or ""

  local current_buf = vim.api.nvim_get_current_buf()
  local is_terminal_buf = vim.bo[current_buf].buftype == "terminal"

  vim.ui.input({
    prompt = "Rename terminal: ",
    default = current_name,
  }, function(input)
    if input and input ~= "" then
      if tabs.rename_terminal(active_id, input) then
        vim.notify("Terminal renamed to: " .. input, vim.log.levels.INFO)
        if is_terminal_buf then
          vim.schedule(function() vim.cmd("startinsert") end)
        end
      else
        vim.notify("Failed to rename terminal", vim.log.levels.ERROR)
      end
    elseif is_terminal_buf then
      vim.schedule(function() vim.cmd("startinsert") end)
    end
  end)
end

function M.list_terminals_handler()
  local terminals = tabs.list_terminals()

  if #terminals == 0 then
    vim.notify("No terminals available. Create one with <leader>an", vim.log.levels.INFO)
    return
  end

  local active_id = tabs.get_active()
  local lines = {"YAPT Terminals:", ""}

  for i, term in ipairs(terminals) do
    local status = terminal.is_running(term.id) and "running" or "stopped"
    local active_marker = (term.id == active_id) and "? " or "  "
    local age_seconds = os.time() - term.created_at
    local age_str

    if age_seconds < 60 then
      age_str = age_seconds .. "s"
    elseif age_seconds < 3600 then
      age_str = math.floor(age_seconds / 60) .. "m"
    else
      age_str = math.floor(age_seconds / 3600) .. "h"
    end

    table.insert(lines, string.format("%s%d. %s [%s] (created %s ago)",
      active_marker, i, term.name, status, age_str))
  end

  table.insert(lines, "")
  table.insert(lines, string.format("Total: %d terminal(s)", #terminals))

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

------------------------------------------------------------
-- Link copy helpers
------------------------------------------------------------

local function copy_range_link_to_clipboard(filepath, start_line, end_line)
  if not filepath or filepath == "" then
    vim.notify("No file path (buffer not saved?)", vim.log.levels.WARN)
    return
  end
  local link = "@" .. filepath .. ":" .. start_line .. "-" .. end_line
  vim.fn.setreg('"', link)
  vim.notify("Copied to buffer: " .. link, vim.log.levels.INFO)
end

local function copy_file_link_to_clipboard(filepath)
  if not filepath or filepath == "" then
    vim.notify("No file path (buffer not saved?)", vim.log.levels.WARN)
    return
  end
  local link = "@" .. filepath
  vim.fn.setreg('"', link)
  vim.notify("Copied to buffer: " .. link, vim.log.levels.INFO)
end

function M.copy_file_link_handler()
  local buf = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(buf)
  copy_file_link_to_clipboard(filepath)
end

function M.copy_link_handler()
  local buf = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(buf)
  local start_line = vim.fn.getpos("'<")[2]
  local end_line = vim.fn.getpos("'>")[2]
  copy_range_link_to_clipboard(filepath, start_line, end_line)
end

------------------------------------------------------------
-- Setup
------------------------------------------------------------

-- Register a single normal-mode keymap with consistent options.
local function set_n(lhs, rhs, desc)
  if not lhs or lhs == "" then return end
  vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
end

local function warn_deprecated_prompt_send_new()
  vim.notify(
    "[yapt] PTPromptSendNew / keybindings.prompt_send_new is deprecated. " ..
    "Create a new terminal with PTNew, then use PTSend.",
    vim.log.levels.WARN
  )
end

function M.setup(user_config)
  config = config_module.setup(user_config)

  local keybindings = config.keybindings

  -- Toggle (split)
  if keybindings.toggle and keybindings.toggle ~= "" then
    set_n(keybindings.toggle, M.normal_mode_handler, "Toggle YAPT terminal")
    vim.keymap.set("v", keybindings.toggle, exit_visual_then(M.visual_mode_handler), {
      desc = "Toggle YAPT terminal and send selection",
      silent = true,
    })
  end

  -- Toggle (fullscreen)
  if keybindings.toggle_fullscreen and keybindings.toggle_fullscreen ~= "" then
    set_n(keybindings.toggle_fullscreen, M.fullscreen_toggle_handler, "Toggle YAPT terminal fullscreen")
    vim.keymap.set("v", keybindings.toggle_fullscreen, exit_visual_then(M.visual_fullscreen_mode_handler), {
      desc = "Toggle YAPT terminal fullscreen and send selection",
      silent = true,
    })
  end

  set_n(keybindings.new, M.new_terminal_handler, "Create new YAPT terminal")
  set_n(keybindings.new_fullscreen, M.new_fullscreen_handler, "Create new YAPT terminal in fullscreen")
  set_n(keybindings.select, M.select_terminal_handler, "Select YAPT terminal")
  set_n(keybindings.rename, M.rename_terminal_handler, "Rename YAPT terminal")

  if keybindings.prompt_new and keybindings.prompt_new ~= "" then
    set_n(keybindings.prompt_new, function()
      history.create_prompt_file(config)
    end, "Create new prompt file in .nvim-yapt/history")
  end

  if keybindings.prompt_send and keybindings.prompt_send ~= "" then
    set_n(keybindings.prompt_send, function()
      history.send_prompt_file_to_terminal(config)
    end, "Send current file contents to YAPT terminal")
  end

  if keybindings.prompt_send_fullscreen and keybindings.prompt_send_fullscreen ~= "" then
    set_n(keybindings.prompt_send_fullscreen, function()
      history.send_prompt_file_to_terminal_fullscreen(config)
    end, "Send current file contents to YAPT terminal (fullscreen)")
  end

  if keybindings.prompt_send_new and keybindings.prompt_send_new ~= "" then
    set_n(keybindings.prompt_send_new, function()
      warn_deprecated_prompt_send_new()
      history.send_prompt_file_to_new_terminal(config)
    end, "Deprecated: send current file contents to new YAPT terminal")
  end

  if keybindings.prompt_history_telescope and keybindings.prompt_history_telescope ~= "" then
    set_n(keybindings.prompt_history_telescope, function()
      history.open_history_in_telescope(config)
    end, "Open prompt history directory in Telescope")
  end

  if keybindings.prompt_last and keybindings.prompt_last ~= "" then
    set_n(keybindings.prompt_last, function()
      history.open_last_prompt_buffer(config)
    end, "Open or switch to last prompt file from history")
  end

  if keybindings.copy_link and keybindings.copy_link ~= "" then
    set_n(keybindings.copy_link, M.copy_file_link_handler, "Copy @file link to clipboard")
    vim.keymap.set("v", keybindings.copy_link, exit_visual_then(M.copy_link_handler), {
      desc = "Copy @file:start-end link to clipboard",
      silent = true,
    })
  end

  ----------------------------------------------------------
  -- User commands
  ----------------------------------------------------------

  vim.api.nvim_create_user_command("PTT", function()
    M.normal_mode_handler()
  end, { desc = "Toggle YAPT terminal (split mode)" })

  vim.api.nvim_create_user_command("PTFullscreen", function()
    M.fullscreen_toggle_handler()
  end, { desc = "Toggle YAPT terminal (fullscreen mode)" })

  vim.api.nvim_create_user_command("PTNew", function(opts)
    local name = opts.args and opts.args ~= "" and opts.args or nil
    picker.pick_command(config, function(cmd)
      tabs.create_terminal(name, config, cmd, "split")
    end)
  end, {
    desc = "Create new YAPT terminal",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("PTNewFullscreen", function()
    M.new_fullscreen_handler()
  end, { desc = "Create new YAPT terminal in fullscreen" })

  vim.api.nvim_create_user_command("PTSelect", function()
    M.select_terminal_handler()
  end, { desc = "Select YAPT terminal" })

  vim.api.nvim_create_user_command("PTRename", function(opts)
    local active_id = tabs.get_active()
    if not active_id then
      vim.notify("No active terminal to rename", vim.log.levels.WARN)
      return
    end

    if opts.args and opts.args ~= "" then
      if tabs.rename_terminal(active_id, opts.args) then
        vim.notify("Terminal renamed to: " .. opts.args, vim.log.levels.INFO)
      end
    else
      M.rename_terminal_handler()
    end
  end, {
    desc = "Rename YAPT terminal",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("PTList", function()
    M.list_terminals_handler()
  end, { desc = "List all YAPT terminals" })

  vim.api.nvim_create_user_command("PTPrompt", function()
    history.create_prompt_file(config)
  end, { desc = "Create new prompt file in .nvim-yapt/history (timestamp in filename)" })

  vim.api.nvim_create_user_command("PTSend", function()
    history.send_prompt_file_to_terminal(config)
  end, { desc = "Send current file contents to YAPT terminal" })

  vim.api.nvim_create_user_command("PTSendFullscreen", function()
    history.send_prompt_file_to_terminal_fullscreen(config)
  end, { desc = "Send current file contents to YAPT terminal (force fullscreen)" })

  -- Deprecated: create new terminal and send current file contents
  vim.api.nvim_create_user_command("PTSendNew", function()
    warn_deprecated_prompt_send_new()
    history.send_prompt_file_to_new_terminal(config)
  end, { desc = "Deprecated: create new YAPT terminal and send current file contents" })

  vim.api.nvim_create_user_command("PTHistory", function()
    history.open_history_in_telescope(config)
  end, { desc = "Open prompt history directory in Telescope" })

  vim.api.nvim_create_user_command("PTLast", function()
    history.open_last_prompt_buffer(config)
  end, { desc = "Open or switch to last prompt file from history" })

  vim.api.nvim_create_user_command("PTCopyLink", function(opts)
    local buf = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(buf)
    local line1 = opts.line1 or vim.api.nvim_win_get_cursor(0)[1]
    local line2 = opts.line2 or line1
    copy_range_link_to_clipboard(filepath, line1, line2)
  end, {
    desc = "Copy @file:start-end link to clipboard (for prompt); range or current line",
    range = true,
  })

  vim.api.nvim_create_user_command("PTSay", function(opts)
    local active_id = tabs.get_active()
    if active_id and terminal.is_running(active_id) then
      terminal.send_text(opts.args, active_id)
    else
      vim.notify("Terminal is not running", vim.log.levels.WARN)
    end
  end, {
    desc = "Send text to YAPT terminal",
    nargs = "+",
  })

  vim.api.nvim_create_user_command("PTVersion", function()
    vim.notify("yapt.nvim v" .. M.version, vim.log.levels.INFO)
  end, { desc = "Display yapt.nvim plugin version" })
end

-- Expose modules for advanced usage
M.terminal = terminal
M.tabs = tabs
M.picker = picker
M.history = history

return M
