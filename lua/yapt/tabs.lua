-- Multi-terminal state management for yapt.nvim plugin
--
-- This module manages the metadata for multiple terminals, providing:
-- - Terminal creation and deletion
-- - Active/last terminal tracking for smart toggling
-- - Terminal renaming and listing
-- - Automatic cleanup via callbacks from terminal.lua
--
-- Architecture:
-- - This module stores metadata (id, name, command, display_mode, timestamps)
-- - The actual terminal buffers/windows are managed by terminal.lua
-- - Cleanup callbacks ensure state stays synchronized when terminals exit
--
local terminal = require("yapt.terminal")
local config_module = require("yapt.config")
local util = require("yapt.util")

local M = {}

local state = {
  terminals = {},      -- Terminal metadata keyed by ID
  active_id = nil,     -- Currently active terminal ID (shown in window)
  last_id = nil,       -- Last active terminal ID (used for smart toggle)
  counter = 0,         -- Counter for generating unique IDs
}

-- Sync metadata when a terminal exits (job dies / user closes it).
terminal.register_cleanup_callback(function(id, _exit_code)
  if state.terminals[id] then
    state.terminals[id] = nil

    if state.active_id == id then
      state.active_id = nil
    end

    if state.last_id == id then
      local list = M.list_terminals()
      if #list > 0 then
        state.last_id = list[1].id
      else
        state.last_id = nil
      end
    end
  end
end)

local function generate_id()
  state.counter = state.counter + 1
  return "term-" .. state.counter
end

local function generate_name(config)
  local prefix = "Term"
  if config and config.terminal and config.terminal.default_name then
    prefix = config.terminal.default_name
  end

  return prefix .. " " .. state.counter
end

-- Create a new terminal.
-- @param name string|nil Custom name for the terminal
-- @param config table Configuration object
-- @param command string|nil Command to launch (resolved if nil)
-- @param display_mode string|nil "split" (default) or "fullscreen"
-- @return string terminal_id
function M.create_terminal(name, config, command, display_mode)
  display_mode = display_mode or "split"
  local id = generate_id()

  if not name or name == "" then
    name = generate_name(config)
  end

  local cmd = config_module.resolve_command(command, config)

  state.terminals[id] = {
    id = id,
    name = name,
    command = cmd,
    display_mode = display_mode,
    created_at = os.time(),
    last_active = os.time(),
  }

  terminal._create_terminal_instance(id, config, cmd, display_mode)

  state.active_id = id
  state.last_id = id
  terminal._set_active(id)

  return id
end

function M.get_terminal(id)
  return state.terminals[id]
end

function M.list_terminals()
  local list = {}
  for _, term in pairs(state.terminals) do
    table.insert(list, term)
  end

  table.sort(list, function(a, b)
    return a.last_active > b.last_active
  end)

  return list
end

function M.get_active()
  return state.active_id
end

-- Switch to a specific terminal.
--
-- The target's display mode is determined by `override_mode` if provided;
-- otherwise it follows the *current* presentation mode (fullscreen if a
-- fullscreen terminal is active, split otherwise).
--
-- leave_ui_mode: optional "t"/"n" for the terminal being left. When set,
-- persists that mode on hide() and on same-terminal refocus (so post-picker
-- "n" from leave_terminal_job_mode does not clobber the invoking mode).
-- leave_id: optional terminal to tear down / refocus as "current" when it
-- differs from state.active_id (focused buffer captured before a modal UI).
function M.switch_to(id, config, override_mode, leave_ui_mode, leave_id)
  if not state.terminals[id] then
    util.notify("Terminal " .. id .. " does not exist", vim.log.levels.ERROR)
    return false
  end

  local target_mode = override_mode
    or (terminal.is_fullscreen_in_current_tab() and "fullscreen" or "split")

  local leaving = leave_id or state.active_id
  local is_currently_visible = terminal.is_visible(id)

  if id == leaving and is_currently_visible then
    state.active_id = id
    state.last_id = id
    state.terminals[id].last_active = os.time()
    terminal._set_active(id)
    if leave_ui_mode == "t" or leave_ui_mode == "n" then
      terminal.save_ui_state(id, leave_ui_mode)
    end
    -- Refocus only: do not winrestview, or live scrollback position is lost.
    terminal.apply_ui_state(id, { restore_view = false })
    return true
  end

  -- Tear down the terminal we're leaving. Fullscreen must use hide_fullscreen
  -- (restore saved buffer); never nvim_win_hide the taken-over editor window.
  if leaving and leaving ~= id then
    if terminal.is_fullscreen_active(leaving) then
      terminal.hide_fullscreen(leave_ui_mode)
    else
      terminal.hide(leaving, leave_ui_mode)
    end
  end
  -- Also drop a divergent active terminal so focus/active stay aligned.
  if state.active_id and state.active_id ~= id and state.active_id ~= leaving then
    if terminal.is_fullscreen_active(state.active_id) then
      terminal.hide_fullscreen()
    else
      terminal.hide(state.active_id)
    end
  end
  -- Target wants fullscreen: also release any remaining fullscreen surface
  -- (e.g. target itself in another tab, or a third terminal left mounted).
  -- No leave_ui_mode: that mode belongs to the terminal we left, not this one.
  if target_mode == "fullscreen" and terminal.is_fullscreen_active() then
    terminal.hide_fullscreen()
  end

  state.active_id = id
  state.last_id = id
  state.terminals[id].last_active = os.time()
  state.terminals[id].display_mode = target_mode
  terminal._set_active(id)

  local cmd = state.terminals[id].command
  if terminal.is_running(id) then
    -- show / show_fullscreen: never toggle (a visible target must not hide).
    if target_mode == "fullscreen" then
      local term = terminal._get_terminal(id)
      if term and term.win and vim.api.nvim_win_is_valid(term.win) then
        -- Drop existing split (or leftover win) before taking over a window.
        -- Fullscreen for this id was already released above when applicable.
        terminal.hide(id)
        vim.schedule(function()
          if terminal.is_running(id) then
            terminal.show_fullscreen(id)
            terminal.apply_ui_state(id)
          end
        end)
      else
        terminal.show_fullscreen(id)
        terminal.apply_ui_state(id)
      end
    else
      terminal.show(id, config)
      terminal.apply_ui_state(id)
    end
  else
    terminal._create_terminal_instance(id, config, cmd, target_mode)
  end

  return true
end

function M.get_last()
  return state.last_id
end

function M.delete_terminal(id)
  if not state.terminals[id] then
    return false
  end

  if terminal.is_fullscreen_active(id) then
    terminal.hide_fullscreen()
  else
    terminal.hide(id)
  end
  state.terminals[id] = nil

  if state.active_id == id then
    state.active_id = nil
  end

  if state.last_id == id then
    local list = M.list_terminals()
    if #list > 0 then
      state.last_id = list[1].id
    else
      state.last_id = nil
    end
  end

  return true
end

function M.rename_terminal(id, new_name)
  if not state.terminals[id] then
    return false
  end

  if not new_name or new_name == "" then
    util.notify("Terminal name cannot be empty", vim.log.levels.WARN)
    return false
  end

  state.terminals[id].name = new_name
  return true
end

function M.has_terminals()
  return next(state.terminals) ~= nil
end

function M.count()
  local count = 0
  for _ in pairs(state.terminals) do
    count = count + 1
  end
  return count
end

function M.get_state()
  return {
    terminals = state.terminals,
    active_id = state.active_id,
    last_id = state.last_id,
    counter = state.counter,
    count = M.count(),
  }
end

return M
