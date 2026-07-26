-- Terminal picker for yapt.nvim plugin
--
-- Provides fuzzy finder UI for selecting terminals with:
-- - Telescope integration (preferred) with live preview of terminal content
-- - vim.ui.select fallback for users without Telescope
-- - Rename capability directly from picker with <C-r>
-- - Automatic return to terminal insert mode after selection
--
-- Features:
-- - Live preview showing terminal buffer content
-- - Status indicators (running/stopped, age)
-- - Fuzzy search by terminal name
-- - Picker automatically reopens after rename for seamless workflow
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
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          callback(selection.value)
        end
      end)
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
    end
  end)
end

function M.pick_command(config, callback)
  local entries = config_module.resolve_command_entries(config)

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
      -- Default action: select terminal
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          callback(selection.id)
          vim.schedule(function()
            vim.cmd("startinsert")
          end)
        end
      end)

      -- Custom action: rename terminal with <C-r>
      map("i", "<C-r>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          local term = selection.value
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
                else
                  util.notify("Failed to rename terminal", vim.log.levels.ERROR)
                end
              end
            end)
          end)
        end
      end)

      -- Also map <C-r> in normal mode for Telescope
      map("n", "<C-r>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          local term = selection.value
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
                else
                  util.notify("Failed to rename terminal", vim.log.levels.ERROR)
                end
              end
            end)
          end)
        end
      end)

      return true
    end,
  }):find()

  return true
end

-- Pick terminal using vim.ui.select (fallback)
-- @param terminals Array of terminal metadata
-- @param callback function(selected_id) Called with selected terminal ID
local function pick_with_ui_select(terminals, callback)
  local items = {}
  local id_map = {}

  for i, term in ipairs(terminals) do
    items[i] = format_terminal_display(term)
    id_map[i] = term.id
  end

  vim.ui.select(items, {
    prompt = "Select Terminal:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if idx then
      callback(id_map[idx])
      vim.schedule(function()
        vim.cmd("startinsert")
      end)
    end
  end)
end

-- Main picker function - shows terminal selection UI
-- @param config Configuration object
-- @param callback function(selected_id) Called with selected terminal ID
function M.pick_terminal(config, callback)
  local terminals = tabs.list_terminals()

  if #terminals == 0 then
    util.notify("No terminals available. Create one with <leader>an", vim.log.levels.WARN)
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
