-- Terminal picker for yapt.nvim plugin
--
-- Provides fuzzy finder UI for selecting terminals with:
-- - Telescope integration (preferred) with live preview of terminal content
-- - vim.ui.select fallback for users without Telescope
-- - Rename capability directly from picker with <C-r>
-- - callback(nil) on dismiss so callers can restore terminal UI state
--
-- Features:
-- - Live preview showing terminal buffer content
-- - Status indicators (running/stopped, age)
-- - Fuzzy search by terminal name
-- - Picker automatically reopens after rename for seamless workflow
--
-- Focus/insert restoration after selection is left to the caller (apply_ui_state).
--
local tabs = require("yapt.tabs")
local terminal = require("yapt.terminal")
local config_module = require("yapt.config")
local util = require("yapt.util")

local M = {}

local function has_telescope()
  return pcall(require, "telescope")
end

local function pick_command_with_telescope(entries, callback)
  if not has_telescope() then
    return false
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "Select Command",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry.command,
          display = entry.label,
          ordinal = entry.label .. " " .. entry.command,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, _map)
      local settled = false
      local function settle(cmd)
        if settled then
          return
        end
        settled = true
        callback(cmd)
      end

      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        settle(selection and selection.value or nil)
      end)

      -- Dismiss only when the prompt is gone (same pattern as pick_terminal).
      vim.api.nvim_create_autocmd("BufLeave", {
        buffer = prompt_bufnr,
        callback = function()
          vim.schedule(function()
            if settled then
              return
            end
            if vim.api.nvim_buf_is_valid(prompt_bufnr) then
              return
            end
            settle(nil)
          end)
        end,
      })

      return true
    end,
  }):find()

  return true
end

local function pick_command_with_ui_select(entries, callback)
  local labels = {}
  for _, e in ipairs(entries) do
    table.insert(labels, e.label)
  end

  vim.ui.select(labels, {
    prompt = "Select Command:",
  }, function(_, idx)
    if idx then
      callback(entries[idx].command)
    else
      callback(nil)
    end
  end)
end

-- @param callback function(cmd|nil) Called with command, or nil on cancel/dismiss
function M.pick_command(config, callback)
  local entries = config_module.resolve_command_entries(config)

  if #entries == 0 then
    callback(nil)
    return
  end

  if #entries == 1 then
    callback(entries[1].command)
    return
  end

  local success = pick_command_with_telescope(entries, callback)
  if success then
    return
  end

  pick_command_with_ui_select(entries, callback)
end

-- Format terminal info for display in picker
-- @param term Terminal metadata object
-- @return string Formatted display string
local function format_terminal_display(term)
  local status_icon
  local status_text

  if terminal.is_running(term.id) then
    status_icon = "?"
    status_text = "running"
  else
    status_icon = "?"
    status_text = "stopped"
  end

  -- Calculate age
  local age_seconds = os.time() - term.created_at
  local age_str
  if age_seconds < 60 then
    age_str = age_seconds .. "s ago"
  elseif age_seconds < 3600 then
    age_str = math.floor(age_seconds / 60) .. "m ago"
  else
    age_str = math.floor(age_seconds / 3600) .. "h ago"
  end

  return string.format("%s %s (%s, %s)", status_icon, term.name, status_text, age_str)
end

-- Toggle target in an MRU-sorted list: previous when current is first, else first.
-- Used so F6+Enter switches between the last two terminals.
local function toggle_selection_index(terminals)
  local current_id = terminal.id_for_buf() or tabs.get_active() or tabs.get_last()
  if current_id and terminals[1] and terminals[1].id == current_id and terminals[2] then
    return 2
  end
  return 1
end

-- Pick terminal using Telescope (if available)
-- @param terminals Array of terminal metadata
-- @param config Configuration object
-- @param callback function(selected_id) Called with selected terminal ID
local function pick_with_telescope(terminals, config, callback)
  local ok, telescope = pcall(require, "telescope")
  if not ok then
    return false
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  -- Build entries for telescope
  local entries = {}
  for _, term in ipairs(terminals) do
    table.insert(entries, {
      id = term.id,
      display = format_terminal_display(term),
      ordinal = term.name,  -- For searching/filtering
      value = term,
    })
  end

  -- Create a custom previewer for terminal buffers
  local terminal_previewer = previewers.new_buffer_previewer({
    title = "Terminal Preview",
    define_preview = function(self, entry, status)
      -- Get the terminal info
      local term_info = terminal._get_terminal(entry.id)

      if term_info and term_info.buf and vim.api.nvim_buf_is_valid(term_info.buf) then
        -- Get terminal buffer lines
        local lines = vim.api.nvim_buf_get_lines(term_info.buf, 0, -1, false)

        -- Set lines in preview buffer
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

        -- Optional: Set filetype for syntax highlighting
        vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'terminal')
      else
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
          "Terminal not running",
          "",
          "Status: " .. (terminal.is_running(entry.id) and "running" or "stopped")
        })
      end
    end,
  })

  pickers.new({}, {
    prompt_title = "Select Terminal",
    default_selection_index = toggle_selection_index(terminals),
    -- Keep preselect on empty prompt; follow best match while filtering.
    selection_strategy = "closest",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry.value,
          display = entry.display,
          ordinal = entry.ordinal,
          id = entry.id,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = terminal_previewer,
    attach_mappings = function(prompt_bufnr, map)
      local settled = false
      local function settle(id)
        if settled then
          return
        end
        settled = true
        callback(id)
      end

      -- Default action: select terminal (caller restores focus via apply_ui_state).
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        settle(selection and selection.id or nil)
      end)

      -- Rename via <C-r>: not a dismiss. Reopen on success; callback(nil) otherwise.
      local function rename_selected()
        local selection = action_state.get_selected_entry()
        if not selection then
          return
        end
        local term = selection.value
        settled = true
        actions.close(prompt_bufnr)

        vim.schedule(function()
          vim.ui.input({
            prompt = "Rename terminal: ",
            default = term.name,
          }, function(input)
            if input and input ~= "" then
              if tabs.rename_terminal(selection.id, input) then
                util.notify("Terminal renamed to: " .. input, vim.log.levels.INFO)
                vim.schedule(function()
                  M.pick_terminal(config, callback)
                end)
                return
              end
              util.notify("Failed to rename terminal", vim.log.levels.ERROR)
            end
            callback(nil)
          end)
        end)
      end

      map("i", "<C-r>", rename_selected)
      map("n", "<C-r>", rename_selected)

      -- Dismiss only when the prompt is gone. Transient BufLeave (preview
      -- focus, <C-w>) must not settle, or a later <CR> would be ignored.
      -- Not once: a skipped transient leave must still observe the real close.
      vim.api.nvim_create_autocmd("BufLeave", {
        buffer = prompt_bufnr,
        callback = function()
          vim.schedule(function()
            if settled then
              return
            end
            if vim.api.nvim_buf_is_valid(prompt_bufnr) then
              return
            end
            settle(nil)
          end)
        end,
      })

      return true
    end,
  }):find()

  return true
end

-- Pick terminal using vim.ui.select (fallback)
-- @param terminals Array of terminal metadata
-- @param callback function(selected_id|nil) Called with id, or nil on cancel
local function pick_with_ui_select(terminals, callback)
  local items = {}
  local id_map = {}

  -- vim.ui.select always starts on the first item: put the toggle target first.
  local prefer = toggle_selection_index(terminals)
  local order = { prefer }
  for i = 1, #terminals do
    if i ~= prefer then
      order[#order + 1] = i
    end
  end
  for new_i, old_i in ipairs(order) do
    items[new_i] = format_terminal_display(terminals[old_i])
    id_map[new_i] = terminals[old_i].id
  end

  vim.ui.select(items, {
    prompt = "Select Terminal:",
    format_item = function(item)
      return item
    end,
  }, function(_, idx)
    if idx then
      callback(id_map[idx])
    else
      callback(nil)
    end
  end)
end

-- Main picker function - shows terminal selection UI
-- @param config Configuration object
-- @param callback function(selected_id|nil) Called with id, or nil on cancel/dismiss
function M.pick_terminal(config, callback)
  local terminals = tabs.list_terminals()

  if #terminals == 0 then
    util.notify("No terminals available. Create one with <leader>an", vim.log.levels.WARN)
    callback(nil)
    return
  end

  if #terminals == 1 then
    callback(terminals[1].id)
    return
  end

  if has_telescope() then
    local success = pick_with_telescope(terminals, config, callback)
    if success then
      return
    end
  end

  pick_with_ui_select(terminals, callback)
end

return M
